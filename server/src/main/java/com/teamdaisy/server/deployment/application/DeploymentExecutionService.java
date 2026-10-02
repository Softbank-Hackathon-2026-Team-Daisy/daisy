package com.teamdaisy.server.deployment.application;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ObjectNode;
import com.teamdaisy.server.ai.application.AiUsageService;
import com.teamdaisy.server.common.error.DaisyException;
import com.teamdaisy.server.common.error.ErrorCode;
import com.teamdaisy.server.common.json.CanonicalJson;
import com.teamdaisy.server.deployment.domain.*;
import com.teamdaisy.server.deployment.infrastructure.DeploymentStore;
import com.teamdaisy.server.history.application.DeploymentEvent;
import com.teamdaisy.server.history.application.EventJournal;
import com.teamdaisy.server.idempotency.application.IdempotencyService;
import com.teamdaisy.server.jenkins.application.JenkinsCommandService;
import com.teamdaisy.server.jenkins.application.JenkinsCommandService.CommandScope;
import com.teamdaisy.server.jenkins.application.JenkinsCommandService.CommandTarget;
import com.teamdaisy.server.script.application.ScriptService;
import java.time.Instant;
import java.util.*;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/** Internal API: callback methods are invoked only after the adapter authenticates its sender. */
@Service
@Transactional
public class DeploymentExecutionService {
  public record CreateRequest(
      String actorId,
      String projectId,
      String sourceVersionId,
      List<String> targetIds,
      JsonNode input,
      String idempotencyKey) {}

  public record Decision(String approvalId, boolean approved, String confirmationText) {}

  public record DecisionRequest(
      String actorId,
      String projectId,
      String deploymentId,
      Map<String, Decision> decisions,
      String idempotencyKey) {}

  public record ControlRequest(
      String actorId,
      String projectId,
      String deploymentId,
      List<String> targetIds,
      String idempotencyKey) {}

  public record RollbackRequest(
      String actorId,
      String projectId,
      String sourceDeploymentId,
      String triggerDeploymentId,
      List<String> targetIds,
      String reason,
      String idempotencyKey) {}

  public record BuildResult(
      String projectId,
      String deploymentId,
      String executionId,
      String source,
      String sourceEventId,
      String sourceVersionId,
      String commitSha,
      JsonNode imageRefs,
      Instant occurredAt) {}

  public record PlanResult(
      String projectId,
      String deploymentId,
      String executionId,
      String deploymentTargetId,
      String source,
      String sourceEventId,
      long sourceSequence,
      String sourcePlanId,
      String inputHash,
      String scriptId,
      boolean reusedScript,
      int attempt,
      String artifactRef,
      String digest,
      JsonNode summary,
      JsonNode resources,
      Instant expiresAt,
      Instant artifactExpiresAt,
      Instant occurredAt) {
    public PlanResult {
      if (expiresAt != null)
        expiresAt = expiresAt.truncatedTo(java.time.temporal.ChronoUnit.MICROS);
      if (artifactExpiresAt != null)
        artifactExpiresAt = artifactExpiresAt.truncatedTo(java.time.temporal.ChronoUnit.MICROS);
    }
  }

  public record StateResult(
      String projectId,
      String deploymentId,
      String executionId,
      String deploymentTargetId,
      String source,
      String sourceEventId,
      long sourceSequence,
      DeploymentTargetStatus status,
      int attempt,
      String errorSummary,
      JsonNode result,
      Instant occurredAt) {}

  public record StaleResult(
      String projectId,
      String deploymentId,
      String executionId,
      String deploymentTargetId,
      String source,
      String sourceEventId,
      long sourceSequence,
      String planId,
      String planDigest,
      String inputHash,
      boolean confirmedNotApplied,
      boolean executionTerminated,
      Instant occurredAt) {}

  private final DeploymentStore store;
  private final JenkinsCommandService commands;
  private final EventJournal journal;
  private final IdempotencyService idempotency;
  private final ObjectProvider<ExecutionAccess> access;
  private final ObjectProvider<ExecutionInputs> inputs;
  private final ScriptService scripts;
  private final AiUsageService usage;
  private final ObjectMapper mapper;
  private final CanonicalJson json;

  public DeploymentExecutionService(
      DeploymentStore store,
      JenkinsCommandService commands,
      EventJournal journal,
      IdempotencyService idempotency,
      ObjectProvider<ExecutionAccess> access,
      ObjectProvider<ExecutionInputs> inputs,
      ScriptService scripts,
      AiUsageService usage,
      ObjectMapper mapper,
      CanonicalJson json) {
    this.store = store;
    this.commands = commands;
    this.journal = journal;
    this.idempotency = idempotency;
    this.access = access;
    this.inputs = inputs;
    this.scripts = scripts;
    this.usage = usage;
    this.mapper = mapper;
    this.json = json;
  }

  public IdempotencyService.Response create(CreateRequest request) {
    requireWrite(request.actorId(), request.projectId());
    safeText(request.sourceVersionId(), 64, false);
    List<String> selected = ids(request.targetIds());
    JsonNode body =
        mapper.valueToTree(
            Map.of(
                "source_version_id",
                request.sourceVersionId(),
                "target_ids",
                selected,
                "input",
                json.copy(request.input())));
    return idempotency.execute(
        request.actorId(),
        request.projectId(),
        "create",
        "project",
        request.idempotencyKey(),
        body,
        () -> {
          var captured =
              inputPort()
                  .capture(
                      request.actorId(),
                      request.projectId(),
                      request.sourceVersionId(),
                      selected,
                      request.input());
          require(captured != null && captured.targets() != null, ErrorCode.STATE_CONFLICT);
          require(
              captured.source() != null
                  && request.sourceVersionId().equals(captured.source().sourceVersionId()),
              ErrorCode.STATE_CONFLICT);
          require(
              captured.targets().stream()
                  .map(ExecutionInputs.TargetInput::id)
                  .sorted()
                  .toList()
                  .equals(selected),
              ErrorCode.STATE_CONFLICT);
          Instant now = Instant.now();
          Deployment deployment =
              Deployment.create(
                  id("dep"),
                  request.projectId(),
                  request.actorId(),
                  captured.source().commitSha(),
                  captured.repository(),
                  captured.commonInput(),
                  json.hash(body),
                  now);
          store.save(deployment);
          List<DeploymentTarget> targets = new ArrayList<>();
          require(
              captured.targets().stream()
                      .map(ExecutionInputs.TargetInput::stateIdentity)
                      .distinct()
                      .count()
                  == selected.size(),
              ErrorCode.STATE_CONFLICT);
          for (var source : captured.targets()) {
            var target =
                DeploymentTarget.create(
                    id("dt"), deployment, source.id(), source.snapshot(), source.stateIdentity());
            targets.add(target);
            store.save(target);
          }
          bindSource(deployment, targets, captured.source());
          store.flush();
          var command = prepare(deployment, targets, false);
          internal(
              deployment,
              null,
              command.id(),
              "deployment.created",
              payload(deployment).put("request_id", command.requestId()),
              null,
              now);
          return response(deployment, 201);
        });
  }

  public IdempotencyService.Response decide(DecisionRequest request) {
    requireWrite(request.actorId(), request.projectId());
    require(
        request.decisions() != null && !request.decisions().isEmpty(), ErrorCode.VALIDATION_FAILED);
    return idempotency.execute(
        request.actorId(),
        request.projectId(),
        "decide",
        request.deploymentId(),
        request.idempotencyKey(),
        mapper.valueToTree(request.decisions()),
        () -> {
          Deployment deployment = store.lock(request.projectId(), request.deploymentId());
          List<DeploymentTarget> all = store.targets(deployment.id());
          require(
              request.decisions().values().stream().allMatch(Objects::nonNull)
                  && request.decisions().values().stream()
                          .map(Decision::approved)
                          .distinct()
                          .count()
                      == 1,
              ErrorCode.VALIDATION_FAILED);
          require(
              new HashSet<>(
                      all.stream()
                          .filter(t -> t.status() == DeploymentTargetStatus.AWAITING_APPROVAL)
                          .map(DeploymentTarget::targetId)
                          .toList())
                  .equals(request.decisions().keySet()),
              ErrorCode.STATE_CONFLICT);
          List<DeploymentTarget> selected = select(all, request.decisions().keySet());
          require(
              selected.stream()
                      .map(t -> store.approvalForPlan(t.currentPlanId()).confirmationText())
                      .distinct()
                      .count()
                  == 1,
              ErrorCode.STATE_CONFLICT);
          Instant now = Instant.now();
          List<DeploymentTarget> approved = new ArrayList<>();
          for (var target : selected) {
            Decision decision = request.decisions().get(target.targetId());
            require(decision != null, ErrorCode.VALIDATION_FAILED);
            var approval = store.approvalForPlan(target.currentPlanId());
            require(approval.id().equals(decision.approvalId()), ErrorCode.STATE_CONFLICT);
            require(target.currentPlanId() != null, ErrorCode.STATE_CONFLICT);
            var plan = store.plan(target.currentPlanId());
            scripts.requireScript(plan.scriptId(), deployment.projectId(), target.targetId(), now);
            approval.decide(
                plan,
                target,
                request.actorId(),
                decision.approved(),
                decision.confirmationText(),
                now);
            if (decision.approved()) approved.add(target);
            else {
              requireSafeToReplace(target);
              target.confirmCancellation(now);
            }
          }
          store.flush();
          String execution = null;
          if (!approved.isEmpty()) {
            var applyTargets =
                approved.stream()
                    .map(t -> commandTarget(t, store.plan(t.currentPlanId())))
                    .toList();
            ObjectNode command =
                commandPayload(deployment, approved)
                    .put("approval_policy", "atomic_pending_targets");
            var plans = command.putArray("plans");
            for (var target : approved) {
              var plan = store.plan(target.currentPlanId());
              plans
                  .addObject()
                  .put("deployment_target_id", target.id())
                  .put("plan_id", plan.id())
                  .put("artifact_ref", plan.artifactRef())
                  .put("digest", plan.digest())
                  .put("input_hash", plan.inputHash());
            }
            var ref = commands.enqueue(deployment.id(), "apply", null, applyTargets, command);
            execution = ref.id();
            for (var target : approved) target.attachExecution(execution);
          }
          deployment.aggregate(all, now);
          store.flush();
          for (var target : selected)
            internal(
                deployment,
                target,
                request.decisions().get(target.targetId()).approved() ? execution : null,
                "approval.resolved",
                payload(deployment, target)
                    .put("approval_id", request.decisions().get(target.targetId()).approvalId())
                    .put(
                        "state",
                        request.decisions().get(target.targetId()).approved()
                            ? "approved"
                            : "rejected"),
                null,
                now);
          stateEvent(deployment, now);
          return response(deployment, 202);
        });
  }

  public IdempotencyService.Response cancel(ControlRequest request) {
    requireWrite(request.actorId(), request.projectId());
    List<String> ids = ids(request.targetIds());
    return idempotency.execute(
        request.actorId(),
        request.projectId(),
        "cancel",
        request.deploymentId(),
        request.idempotencyKey(),
        mapper.valueToTree(ids),
        () -> {
          Deployment deployment = store.lock(request.projectId(), request.deploymentId());
          List<DeploymentTarget> all = store.targets(deployment.id());
          List<DeploymentTarget> selected = select(all, new HashSet<>(ids));
          Instant now = Instant.now();
          for (var target : selected) target.requestCancellation(request.actorId(), now);
          // A command may span targets; cancelling its submission affects every linked target.
          Map<String, List<DeploymentTarget>> groups = new TreeMap<>();
          for (var target : selected) {
            require(target.currentExecutionId() != null, ErrorCode.STATE_CONFLICT);
            groups
                .computeIfAbsent(target.currentExecutionId(), key -> new ArrayList<>())
                .add(target);
          }
          for (var group : groups.entrySet()) {
            var scope = commands.lookup(group.getKey());
            boolean wholeCommand =
                commands.executionTargets(scope.id()).stream()
                    .allMatch(
                        t ->
                            group.getValue().stream()
                                .anyMatch(s -> s.id().equals(t.deploymentTargetId())));
            boolean notSubmitted = wholeCommand && commands.cancelPending(scope.id());
            // Once APPLY may have reached Jenkins, record intent only; never stop the run.
            if (scope.operation().equals("apply") && !notSubmitted) {
              // A pending shared command cannot cancel only some targets without resubmission.
              require(
                  !scope.dispatchStatus().equals("pending") || wholeCommand,
                  ErrorCode.STATE_CONFLICT);
              continue;
            }
            require(
                commands.executionTargets(scope.id()).stream()
                    .allMatch(
                        t ->
                            group.getValue().stream()
                                    .anyMatch(s -> s.id().equals(t.deploymentTargetId()))
                                || find(all, t.deploymentTargetId()).status().terminal()),
                ErrorCode.STATE_CONFLICT);
            if (notSubmitted) {
              for (var target : group.getValue()) {
                target.confirmCancellation(now);
                invalidateCurrent(target, "cancelled", now);
                commands.recordTargetState(
                    scope.id(),
                    target.id(),
                    "cancelled",
                    target.lastSourceSequence() == null ? 0 : target.lastSourceSequence() + 1,
                    now,
                    true);
                store.flush();
                String evidence =
                    internal(
                        deployment,
                        target,
                        scope.id(),
                        "target.status_changed",
                        payload(deployment, target).put("reason", "confirmed_not_submitted"),
                        null,
                        now);
                commands.releaseOwnedLock(scope.id(), target.id(), "backend", evidence);
              }
            } else if (!scope.operation().equals("apply")
                && group.getValue().stream().allMatch(t -> executionFinished(scope, t))) {
              for (var target : group.getValue()) {
                target.confirmCancellation(now);
                invalidateCurrent(target, "cancelled", now);
              }
            } else
              commands.enqueue(
                  deployment.id(),
                  "stop",
                  scope.id(),
                  group.getValue().stream().map(t -> commandTarget(t, null)).toList(),
                  commandPayload(deployment, group.getValue()));
          }
          deployment.aggregate(all, now);
          store.flush();
          stateEvent(deployment, now);
          return response(deployment, 202);
        });
  }

  public IdempotencyService.Response retry(ControlRequest request) {
    requireWrite(request.actorId(), request.projectId());
    List<String> selectedIds = ids(request.targetIds());
    return idempotency.execute(
        request.actorId(),
        request.projectId(),
        "retry",
        request.deploymentId(),
        request.idempotencyKey(),
        mapper.valueToTree(selectedIds),
        () -> {
          Deployment original = store.lock(request.projectId(), request.deploymentId());
          var originals = select(store.targets(original.id()), new HashSet<>(selectedIds));
          require(
              originals.stream().allMatch(t -> t.status() == DeploymentTargetStatus.FAILED),
              ErrorCode.STATE_CONFLICT);
          inputPort()
              .verifyFrozen(request.actorId(), request.projectId(), frozen(original, originals));
          Instant now = Instant.now();
          var deployment =
              Deployment.retry(
                  id("dep"),
                  request.actorId(),
                  original,
                  json.hash(mapper.valueToTree(selectedIds)),
                  now);
          store.save(deployment);
          List<DeploymentTarget> targets = new ArrayList<>();
          for (var originalTarget : originals) {
            var target = DeploymentTarget.retry(id("dt"), deployment, originalTarget);
            store.save(target);
            targets.add(target);
          }
          store.flush();
          var command = prepare(deployment, targets, false);
          internal(
              deployment,
              null,
              command.id(),
              "deployment.created",
              payload(deployment).put("reason", "retry"),
              null,
              now);
          return response(deployment, 201);
        });
  }

  public IdempotencyService.Response rollback(RollbackRequest request) {
    requireWrite(request.actorId(), request.projectId());
    List<String> selectedIds = ids(request.targetIds());
    safeText(request.reason(), 1000, false);
    ObjectNode body =
        mapper
            .createObjectNode()
            .put("source_deployment_id", request.sourceDeploymentId())
            .put("reason", request.reason());
    body.set("target_ids", mapper.valueToTree(selectedIds));
    if (request.triggerDeploymentId() != null)
      body.put("trigger_deployment_id", request.triggerDeploymentId());
    return idempotency.execute(
        request.actorId(),
        request.projectId(),
        "rollback",
        request.sourceDeploymentId(),
        request.idempotencyKey(),
        body,
        () -> {
          // Same project lock serializes the two lineage rows before any target locks are taken.
          Deployment original = store.lock(request.projectId(), request.sourceDeploymentId());
          if (request.triggerDeploymentId() != null)
            store.lock(request.projectId(), request.triggerDeploymentId());
          List<DeploymentTarget> allOriginals = store.targets(original.id());
          require(
              !allOriginals.isEmpty()
                  && allOriginals.stream()
                      .allMatch(t -> t.status() == DeploymentTargetStatus.SUCCEEDED),
              ErrorCode.STATE_CONFLICT);
          List<DeploymentTarget> originals = select(allOriginals, new HashSet<>(selectedIds));
          inputPort()
              .verifyFrozen(request.actorId(), request.projectId(), frozen(original, originals));
          Instant now = Instant.now();
          for (var target : originals)
            scripts.requireScript(target.scriptId(), original.projectId(), target.targetId(), now);
          var deployment =
              Deployment.rollback(
                  id("dep"),
                  request.actorId(),
                  original,
                  request.triggerDeploymentId(),
                  json.hash(body),
                  now);
          store.save(deployment);
          List<DeploymentTarget> targets = new ArrayList<>();
          for (var old : originals) {
            var target = DeploymentTarget.rollback(id("dt"), deployment, old);
            store.save(target);
            targets.add(target);
          }
          store.flush();
          var command = prepare(deployment, targets, true);
          internal(
              deployment,
              null,
              command.id(),
              "deployment.created",
              payload(deployment).put("reason", request.reason()),
              null,
              now);
          return response(deployment, 201);
        });
  }

  public void bindBuildResult(BuildResult result) {
    json.copy(mapper.valueToTree(result));
    Deployment deployment = store.lock(result.projectId(), result.deploymentId());
    var scope = commands.requireScope(result.executionId(), deployment.id(), null);
    require(
        scope.projectId().equals(result.projectId()) && scope.operation().equals("prepare"),
        ErrorCode.STATE_CONFLICT);
    require(deployment.commitSha().equals(result.commitSha()), ErrorCode.STATE_CONFLICT);
    require(
        Objects.equals(deployment.sourceVersionId(), result.sourceVersionId()),
        ErrorCode.STATE_CONFLICT);
    var targets = store.targets(deployment.id());
    ObjectNode payload =
        mapper
            .createObjectNode()
            .put("deployment_id", deployment.id())
            .put("execution_id", scope.id())
            .put("source_version_id", result.sourceVersionId())
            .put("receipt_hash", json.hash(mapper.valueToTree(result)));
    var event =
        event(
            result.source(),
            result.sourceEventId(),
            null,
            scope.id(),
            null,
            "build.received",
            payload,
            "applied",
            result.occurredAt());
    if (journal.appendDeployment(deployment.projectId(), deployment.id(), event, true).duplicate())
      return;
    var confirmed = inputPort().recordBuild(result);
    require(
        confirmed != null
            && Objects.equals(confirmed.sourceVersionId(), result.sourceVersionId())
            && Objects.equals(confirmed.commitSha(), result.commitSha())
            && confirmed.imageRefs() != null
            && confirmed.imageRefs().equals(result.imageRefs()),
        ErrorCode.STATE_CONFLICT);
    bindSource(deployment, targets, confirmed);
    store.flush();
  }

  public void acceptPlan(PlanResult result) {
    json.copy(mapper.valueToTree(result));
    Deployment deployment = store.lock(result.projectId(), result.deploymentId());
    var all = store.targets(deployment.id());
    var target = find(all, result.deploymentTargetId());
    var scope = commands.requireScope(result.executionId(), deployment.id(), target.id());
    require(
        scope.projectId().equals(result.projectId())
            && Set.of("prepare", "replan").contains(scope.operation()),
        ErrorCode.STATE_CONFLICT);
    require(
        result.sourceSequence() >= 0
            && result.attempt() >= 0
            && result.attempt() <= 3
            && (!result.reusedScript() || result.attempt() == 0),
        ErrorCode.VALIDATION_FAILED);
    boolean stale = stale(target, scope.id(), result.sourceSequence());
    var payload =
        mapper
            .createObjectNode()
            .put("deployment_id", deployment.id())
            .put("deployment_target_id", target.id())
            .put("target_id", target.targetId())
            .put("digest", result.digest())
            .put("input_hash", result.inputHash())
            .put("receipt_hash", json.hash(mapper.valueToTree(result)));
    var event =
        event(
            result.source(),
            result.sourceEventId(),
            result.sourceSequence(),
            scope.id(),
            target.id(),
            "plan.ready",
            payload,
            stale ? "ignored_stale" : "applied",
            result.occurredAt());
    if (journal.appendDeployment(deployment.projectId(), deployment.id(), event, false).duplicate())
      return;
    PlanRevision previous = store.sourcePlan(result.source(), result.sourcePlanId());
    if (previous != null) {
      require(samePlan(previous, result), ErrorCode.STATE_CONFLICT);
      if (!stale && previous.id().equals(target.currentPlanId())) {
        require(
            target.aiReused() == result.reusedScript() && target.attempt() == result.attempt(),
            ErrorCode.STATE_CONFLICT);
        target.applyStatus(
            scope.id(),
            result.sourceSequence(),
            DeploymentTargetStatus.AWAITING_APPROVAL,
            result.attempt(),
            null,
            null,
            Instant.now());
        store.flush();
      }
      return;
    }
    if (stale) return;
    require(
        deployment.resolvedInputHash() != null
            && target.inputHash() != null
            && target.inputHash().equals(result.inputHash()),
        ErrorCode.STATE_CONFLICT);
    scripts.requireScript(
        result.scriptId(), deployment.projectId(), target.targetId(), Instant.now());
    Instant now = Instant.now();
    invalidateCurrent(target, "new_plan", now);
    store.flush();
    var plan =
        PlanRevision.create(
            id("plan"),
            target.id(),
            scope.id(),
            deployment.projectId(),
            target.targetId(),
            store.nextRevision(target.id()),
            result.source(),
            result.sourcePlanId(),
            result.inputHash(),
            result.scriptId(),
            result.artifactRef(),
            result.digest(),
            result.summary(),
            result.resources(),
            now,
            result.expiresAt(),
            result.artifactExpiresAt());
    var approval =
        Approval.pending(
            id("apv"),
            plan,
            now,
            plan.expiresAt(),
            inputPort().projectName(deployment.projectId()));
    store.save(plan);
    store.save(approval);
    store.flush();
    target.applyStatus(
        scope.id(),
        result.sourceSequence(),
        DeploymentTargetStatus.VALIDATING,
        result.attempt(),
        null,
        null,
        now);
    target.adoptPlan(plan, now);
    deployment.aggregate(all, now);
    store.flush();
    target.recordReuse(result.reusedScript(), usage.hasUsage(target.id()));
    store.flush();
    internal(
        deployment,
        target,
        scope.id(),
        "approval.required",
        payload(deployment, target)
            .put("plan_id", plan.id())
            .put("approval_id", approval.id())
            .put("expires_at", plan.expiresAt().toString()),
        null,
        now);
    stateEvent(deployment, now);
  }

  public void acceptState(StateResult result) {
    validateResult(result.result());
    safeText(result.errorSummary(), 16384, true);
    json.copy(mapper.valueToTree(result));
    require(result.status() != null, ErrorCode.VALIDATION_FAILED);
    Deployment deployment = store.lock(result.projectId(), result.deploymentId());
    var all = store.targets(deployment.id());
    var target = find(all, result.deploymentTargetId());
    var scope = commands.requireScope(result.executionId(), deployment.id(), target.id());
    require(scope.projectId().equals(result.projectId()), ErrorCode.STATE_CONFLICT);
    require(!scope.operation().equals("stop"), ErrorCode.STATE_CONFLICT);
    boolean stale = stale(target, scope.id(), result.sourceSequence());
    ObjectNode payload =
        mapper
            .createObjectNode()
            .put("deployment_id", deployment.id())
            .put("deployment_target_id", target.id())
            .put("target_id", target.targetId())
            .put("status", result.status().code())
            .put("attempt", result.attempt())
            .put("receipt_hash", json.hash(mapper.valueToTree(result)));
    var event =
        event(
            result.source(),
            result.sourceEventId(),
            result.sourceSequence(),
            scope.id(),
            target.id(),
            "target.status_changed",
            payload,
            stale ? "ignored_stale" : "applied",
            result.occurredAt());
    if (journal.appendDeployment(deployment.projectId(), deployment.id(), event, true).duplicate()
        || stale) return;
    validateOperation(scope.operation(), result.status());
    if (Set.of(DeploymentTargetStatus.APPLYING, DeploymentTargetStatus.VERIFYING)
        .contains(result.status())) verifyApplyPlan(target, scope);
    if (result.status() == DeploymentTargetStatus.SUCCEEDED)
      verifySuccess(deployment, target, scope, result.result());
    Instant now = Instant.now();
    boolean applied =
        target.applyStatus(
            scope.id(),
            result.sourceSequence(),
            result.status(),
            result.attempt(),
            result.errorSummary(),
            result.result(),
            now);
    require(applied, ErrorCode.STATE_CONFLICT);
    commands.recordTargetState(
        scope.id(),
        target.id(),
        result.status().code(),
        result.sourceSequence(),
        now,
        result.status().terminal());
    deployment.markStarted(now);
    deployment.aggregate(all, now);
    store.flush();
    if (result.status().terminal())
      commands.releaseOwnedLock(scope.id(), target.id(), result.source(), result.sourceEventId());
    stateEvent(deployment, now);
  }

  public void replan(String actor, String project, String deploymentId, String targetId) {
    requireWrite(actor, project);
    Deployment deployment = store.lock(project, deploymentId);
    var all = store.targets(deployment.id());
    var target = find(all, targetId);
    requireSafeToReplace(target);
    Instant now = Instant.now();
    invalidateCurrent(target, "stale", now);
    target.clearPlanForReplan(now);
    store.flush();
    var ref =
        commands.enqueue(
            deployment.id(),
            "replan",
            target.currentExecutionId(),
            List.of(commandTarget(target, null)),
            commandPayload(deployment, List.of(target)));
    target.attachExecution(ref.id());
    deployment.aggregate(all, now);
    store.flush();
    internal(
        deployment,
        target,
        ref.id(),
        "plan.stale",
        payload(deployment, target).put("reason", "stale"),
        null,
        now);
    stateEvent(deployment, now);
  }

  public void expire(String project, String deploymentId, String targetId) {
    Deployment deployment = store.lock(project, deploymentId);
    var all = store.targets(deployment.id());
    var target = find(all, targetId);
    require(target.currentPlanId() != null, ErrorCode.STATE_CONFLICT);
    var plan = store.plan(target.currentPlanId());
    var approval = store.approvalForPlan(plan.id());
    Instant now = Instant.now();
    require(!now.isBefore(approval.expiresAt()), ErrorCode.STATE_CONFLICT);
    requireSafeToReplace(target);
    plan.invalidate("expired", now);
    approval.invalidate("expired", now);
    target.clearCurrentPlan(plan.id());
    target.confirmCancellation(now);
    deployment.aggregate(all, now);
    store.flush();
    internal(
        deployment,
        target,
        target.currentExecutionId(),
        "approval.resolved",
        payload(deployment, target).put("reason", "expired"),
        null,
        now);
    stateEvent(deployment, now);
  }

  public void onCommandRejected(String executionId, String safeReason) {
    var scope = commands.lookup(executionId);
    Deployment deployment = store.lock(scope.projectId(), scope.deploymentId());
    scope = commands.lookup(executionId);
    require(scope.dispatchStatus().equals("rejected"), ErrorCode.STATE_CONFLICT);
    if (scope.operation().equals("stop")) return;
    var all = store.targets(deployment.id());
    Instant now = Instant.now();
    boolean changed = false;
    for (var link : commands.executionTargets(executionId)) {
      var target = find(all, link.deploymentTargetId());
      if (target.status().terminal() || !executionId.equals(target.currentExecutionId())) continue;
      long sequence = target.lastSourceSequence() == null ? 0 : target.lastSourceSequence() + 1;
      boolean expired =
          scope.operation().equals("apply")
              && target.currentPlanId() != null
              && !now.isBefore(store.approvalForPlan(target.currentPlanId()).expiresAt());
      if (expired) {
        invalidateCurrent(target, "expired", now);
        target.confirmCancellation(now);
      } else
        target.applyStatus(
            executionId,
            sequence,
            DeploymentTargetStatus.FAILED,
            target.attempt(),
            "dispatch_rejected",
            null,
            now);
      changed = true;
      commands.recordTargetState(
          executionId, target.id(), expired ? "cancelled" : "failed", sequence, now, true);
      store.flush();
      String evidence =
          internal(
              deployment,
              target,
              executionId,
              "target.status_changed",
              payload(deployment, target)
                  .put(
                      "reason",
                      "confirmed_not_submitted".equals(safeReason)
                          ? "confirmed_not_submitted"
                          : "confirmed_dispatch_rejected"),
              null,
              now);
      commands.releaseOwnedLock(executionId, target.id(), "backend", evidence);
    }
    if (changed) {
      deployment.aggregate(all, now);
      store.flush();
      stateEvent(deployment, now);
    }
  }

  /** A cancelled queue item with no build proves its targets were never executed. */
  public void onQueueCancelled(String executionId) {
    var scope = commands.lookup(executionId);
    Deployment deployment = store.lock(scope.projectId(), scope.deploymentId());
    scope = commands.lookup(executionId);
    require(
        !scope.operation().equals("stop")
            && scope.dispatchStatus().equals("accepted")
            && scope.runStatus().equals("cancelled")
            && scope.queueId() != null
            && scope.buildNumber() == null,
        ErrorCode.STATE_CONFLICT);
    var all = store.targets(deployment.id());
    Instant now = Instant.now();
    boolean changed = false;
    for (var link : commands.executionTargets(executionId)) {
      var target = find(all, link.deploymentTargetId());
      if (target.status().terminal() || !executionId.equals(target.currentExecutionId())) continue;
      long sequence = target.lastSourceSequence() == null ? 0 : target.lastSourceSequence() + 1;
      invalidateCurrent(target, "cancelled", now);
      target.confirmCancellation(now);
      commands.recordTargetState(executionId, target.id(), "cancelled", sequence, now, true);
      store.flush();
      String evidence =
          internal(
              deployment,
              target,
              executionId,
              "target.status_changed",
              payload(deployment, target).put("reason", "confirmed_queue_cancelled"),
              null,
              now);
      commands.releaseOwnedLock(executionId, target.id(), "backend", evidence);
      changed = true;
    }
    if (changed) {
      deployment.aggregate(all, now);
      store.flush();
      stateEvent(deployment, now);
    }
  }

  private JenkinsCommandService.CommandRef prepare(
      Deployment deployment, List<DeploymentTarget> targets, boolean rollback) {
    ObjectNode payload = commandPayload(deployment, targets).put("allow_ai_autofix", !rollback);
    if (rollback) {
      var scripts = payload.putArray("restore_scripts");
      for (var target : targets)
        scripts
            .addObject()
            .put("deployment_target_id", target.id())
            .put("script_id", target.scriptId())
            .put("restored_from_deployment_target_id", target.restoredFromDeploymentTargetId());
    }
    var ref =
        commands.enqueue(
            deployment.id(),
            "prepare",
            null,
            targets.stream().map(t -> commandTarget(t, null)).toList(),
            payload);
    for (var target : targets) target.attachExecution(ref.id());
    store.flush();
    return ref;
  }

  private void bindSource(
      Deployment deployment, List<DeploymentTarget> targets, ExecutionInputs.BuildInput source) {
    ObjectNode resolved =
        mapper
            .createObjectNode()
            .put("hash_format_version", 1)
            .put("commit_sha", deployment.commitSha());
    resolved.set("input", deployment.inputSnapshot());
    resolved.set("repository", deployment.repositorySnapshot());
    resolved.set("image_refs", source.imageRefs());
    deployment.bindSource(
        source.sourceVersionId(), source.commitSha(), source.imageRefs(), json.hash(resolved));
    for (var target : targets) {
      ObjectNode input =
          mapper
              .createObjectNode()
              .put("hash_format_version", 1)
              .put("resolved_input_hash", deployment.resolvedInputHash());
      input.set("target", target.targetSnapshot());
      input.put("state_identity", target.stateIdentity());
      target.bindInput(json.hash(input));
    }
  }

  private ObjectNode commandPayload(Deployment deployment, List<DeploymentTarget> targets) {
    ObjectNode result =
        payload(deployment)
            .put("commit_sha", deployment.commitSha())
            .put("kind", deployment.kind());
    result.set("repository_snapshot", deployment.repositorySnapshot());
    result.set("input_snapshot", deployment.inputSnapshot());
    if (deployment.imageRefs() != null) result.set("image_refs", deployment.imageRefs());
    if (deployment.resolvedInputHash() != null)
      result.put("resolved_input_hash", deployment.resolvedInputHash());
    var snapshots = result.putArray("targets");
    for (var target : targets) {
      var item =
          snapshots
              .addObject()
              .put("deployment_target_id", target.id())
              .put("target_id", target.targetId())
              .put("state_identity", target.stateIdentity());
      item.set("snapshot", target.targetSnapshot());
      if (target.inputHash() != null) item.put("input_hash", target.inputHash());
    }
    return result;
  }

  private CommandTarget commandTarget(DeploymentTarget target, PlanRevision plan) {
    return new CommandTarget(
        target.id(),
        target.inputHash(),
        plan == null ? null : plan.id(),
        plan == null ? null : plan.digest(),
        target.stateIdentity());
  }

  private void requireSafeToReplace(DeploymentTarget target) {
    if (target.currentExecutionId() == null) return;
    var scope = commands.lookup(target.currentExecutionId());
    require(!scope.operation().equals("apply"), ErrorCode.STATE_CONFLICT);
    require(executionFinished(scope, target), ErrorCode.STATE_CONFLICT);
  }

  public void acceptStale(StaleResult result) {
    json.copy(mapper.valueToTree(result));
    Deployment deployment = store.lock(result.projectId(), result.deploymentId());
    var all = store.targets(deployment.id());
    var target = find(all, result.deploymentTargetId());
    var scope = commands.requireScope(result.executionId(), deployment.id(), target.id());
    require(
        scope.projectId().equals(result.projectId())
            && scope.operation().equals("apply")
            && result.confirmedNotApplied()
            && result.executionTerminated(),
        ErrorCode.STATE_CONFLICT);
    var link =
        commands.executionTargets(scope.id()).stream()
            .filter(t -> t.deploymentTargetId().equals(target.id()))
            .findFirst()
            .orElseThrow(() -> new DaisyException(ErrorCode.STATE_CONFLICT));
    require(
        Objects.equals(link.planId(), result.planId())
            && Objects.equals(link.planDigest(), result.planDigest())
            && Objects.equals(link.inputHash(), result.inputHash()),
        ErrorCode.STATE_CONFLICT);
    boolean stale = stale(target, scope.id(), result.sourceSequence());
    ObjectNode payload =
        mapper
            .createObjectNode()
            .put("deployment_id", deployment.id())
            .put("deployment_target_id", target.id())
            .put("target_id", target.targetId())
            .put("status", "stale")
            .put("reason", "stale")
            .put("plan_id", result.planId())
            .put("digest", result.planDigest())
            .put("input_hash", result.inputHash())
            .put("receipt_hash", json.hash(mapper.valueToTree(result)));
    var event =
        event(
            result.source(),
            result.sourceEventId(),
            result.sourceSequence(),
            scope.id(),
            target.id(),
            "plan.stale",
            payload,
            stale ? "ignored_stale" : "applied",
            result.occurredAt());
    if (journal.appendDeployment(deployment.projectId(), deployment.id(), event, false).duplicate()
        || stale) return;
    require(
        Objects.equals(target.currentPlanId(), result.planId())
            && Objects.equals(target.inputHash(), result.inputHash()),
        ErrorCode.STATE_CONFLICT);
    Instant now = Instant.now();
    commands.recordTargetState(
        scope.id(), target.id(), "stale", result.sourceSequence(), now, true);
    commands.releaseOwnedLock(scope.id(), target.id(), result.source(), result.sourceEventId());
    invalidateCurrent(target, "stale", now);
    target.clearPlanForReplan(now);
    store.flush();
    var ref =
        commands.enqueue(
            deployment.id(),
            "replan",
            scope.id(),
            List.of(commandTarget(target, null)),
            commandPayload(deployment, List.of(target)));
    target.attachExecution(ref.id());
    deployment.aggregate(all, now);
    store.flush();
    stateEvent(deployment, now);
  }

  private void validateResult(JsonNode result) {
    if (result == null) return;
    require(result.isObject(), ErrorCode.VALIDATION_FAILED);
    result
        .fieldNames()
        .forEachRemaining(
            key ->
                require(
                    Set.of(
                            "plan_id",
                            "plan_digest",
                            "input_hash",
                            "image_refs",
                            "public_urls",
                            "revision")
                        .contains(key),
                    ErrorCode.VALIDATION_FAILED));
    for (String key : List.of("plan_id", "plan_digest", "input_hash", "revision"))
      if (result.has(key)) {
        require(result.get(key).isTextual(), ErrorCode.VALIDATION_FAILED);
        safeText(result.get(key).asText(), 128, false);
      }
    if (result.has("image_refs")) {
      JsonNode images = result.get("image_refs");
      require(images.isObject() && !images.isEmpty(), ErrorCode.VALIDATION_FAILED);
      images
          .fields()
          .forEachRemaining(
              service -> {
                safeText(service.getKey(), 128, false);
                JsonNode image = service.getValue();
                require(image.isObject(), ErrorCode.VALIDATION_FAILED);
                image
                    .fields()
                    .forEachRemaining(
                        field -> {
                          require(
                              Set.of("image_ref", "digest", "commit_sha").contains(field.getKey())
                                  && field.getValue().isTextual(),
                              ErrorCode.VALIDATION_FAILED);
                          safeText(field.getValue().asText(), 2048, false);
                        });
              });
    }
    if (result.has("public_urls")) {
      require(result.get("public_urls").isObject(), ErrorCode.VALIDATION_FAILED);
      result
          .get("public_urls")
          .fields()
          .forEachRemaining(
              field -> {
                safeText(field.getKey(), 128, false);
                require(field.getValue().isTextual(), ErrorCode.VALIDATION_FAILED);
                String value = field.getValue().asText();
                safeText(value, 2048, false);
                try {
                  var uri = java.net.URI.create(value);
                  require(
                      Set.of("https", "http").contains(uri.getScheme())
                          && uri.getHost() != null
                          && uri.getUserInfo() == null
                          && uri.getQuery() == null
                          && uri.getFragment() == null,
                      ErrorCode.VALIDATION_FAILED);
                } catch (IllegalArgumentException e) {
                  throw new DaisyException(ErrorCode.VALIDATION_FAILED);
                }
              });
    }
  }

  private static void safeText(String value, int max, boolean nullable) {
    if (value == null) {
      require(nullable, ErrorCode.VALIDATION_FAILED);
      return;
    }
    require(
        !value.isBlank()
            && value.length() <= max
            && !java.util.regex.Pattern.compile(
                    "(?i)(-----BEGIN [A-Z ]*PRIVATE KEY|bearer\\s+\\S+|(?:password|secret|token|authorization|credential|access[_-]?key)\\s*[:=]\\s*\\S+|AKIA[A-Z0-9]{16}|gh[pousr]_[A-Za-z0-9]{20,})")
                .matcher(value)
                .find(),
        ErrorCode.VALIDATION_FAILED);
  }

  private boolean executionFinished(CommandScope scope, DeploymentTarget target) {
    return commands.targetFinished(scope.id(), target.id())
        || !scope.operation().equals("apply")
            && Set.of("succeeded", "failed", "cancelled").contains(scope.runStatus());
  }

  private ExecutionInputs.FrozenInput frozen(
      Deployment deployment, List<DeploymentTarget> targets) {
    var source =
        deployment.sourceVersionId() == null
            ? null
            : new ExecutionInputs.BuildInput(
                deployment.sourceVersionId(), deployment.commitSha(), deployment.imageRefs());
    return new ExecutionInputs.FrozenInput(
        deployment.id(),
        deployment.projectId(),
        deployment.commitSha(),
        deployment.repositorySnapshot(),
        deployment.inputSnapshot(),
        source,
        targets.stream()
            .map(
                t ->
                    new ExecutionInputs.FrozenTarget(
                        t.id(),
                        t.targetId(),
                        t.targetSnapshot(),
                        t.stateIdentity(),
                        t.inputHash(),
                        t.scriptId()))
            .toList());
  }

  private void invalidateCurrent(DeploymentTarget target, String reason, Instant now) {
    if (target.currentPlanId() != null) {
      var plan = store.plan(target.currentPlanId());
      plan.invalidate(reason, now);
      store.approvalForPlan(plan.id()).invalidate(reason, now);
      target.clearCurrentPlan(plan.id());
    }
  }

  private boolean samePlan(PlanRevision plan, PlanResult result) {
    return plan.deploymentTargetId().equals(result.deploymentTargetId())
        && plan.inputHash().equals(result.inputHash())
        && plan.scriptId().equals(result.scriptId())
        && plan.artifactRef().equals(result.artifactRef())
        && plan.digest().equals(result.digest())
        && plan.summary().equals(result.summary())
        && plan.resources().equals(result.resources())
        && plan.expiresAt().equals(result.expiresAt())
        && Objects.equals(plan.artifactExpiresAt(), result.artifactExpiresAt());
  }

  private void verifySuccess(
      Deployment deployment, DeploymentTarget target, CommandScope scope, JsonNode result) {
    require(
        scope.operation().equals("apply") && result != null && result.isObject(),
        ErrorCode.STATE_CONFLICT);
    var plan = verifyApplyPlan(target, scope);
    require(
        result.path("plan_id").asText().equals(plan.id())
            && result.path("plan_digest").asText().equals(plan.digest())
            && result.path("input_hash").asText().equals(target.inputHash())
            && deployment.imageRefs().equals(result.path("image_refs")),
        ErrorCode.STATE_CONFLICT);
  }

  private PlanRevision verifyApplyPlan(DeploymentTarget target, CommandScope scope) {
    require(scope.operation().equals("apply"), ErrorCode.STATE_CONFLICT);
    var link =
        commands.executionTargets(scope.id()).stream()
            .filter(t -> t.deploymentTargetId().equals(target.id()))
            .findFirst()
            .orElseThrow(() -> new DaisyException(ErrorCode.STATE_CONFLICT));
    require(
        target.currentPlanId() != null
            && target.inputHash() != null
            && Objects.equals(link.planId(), target.currentPlanId())
            && Objects.equals(link.inputHash(), target.inputHash()),
        ErrorCode.STATE_CONFLICT);
    var plan = store.plan(link.planId());
    require(Objects.equals(link.planDigest(), plan.digest()), ErrorCode.STATE_CONFLICT);
    return plan;
  }

  private static void validateOperation(String operation, DeploymentTargetStatus status) {
    if (operation.equals("apply"))
      require(
          Set.of(
                  DeploymentTargetStatus.APPLYING,
                  DeploymentTargetStatus.VERIFYING,
                  DeploymentTargetStatus.SUCCEEDED,
                  DeploymentTargetStatus.FAILED,
                  DeploymentTargetStatus.CANCELLED)
              .contains(status),
          ErrorCode.STATE_CONFLICT);
    else
      require(
          !Set.of(
                  DeploymentTargetStatus.APPLYING,
                  DeploymentTargetStatus.VERIFYING,
                  DeploymentTargetStatus.SUCCEEDED)
              .contains(status),
          ErrorCode.STATE_CONFLICT);
  }

  private static boolean stale(DeploymentTarget target, String execution, long sequence) {
    require(sequence >= 0, ErrorCode.VALIDATION_FAILED);
    return target.status().terminal()
        || !execution.equals(target.currentExecutionId())
        || target.lastSourceSequence() != null && sequence <= target.lastSourceSequence();
  }

  private void requireWrite(String actor, String project) {
    require(
        actor != null && !actor.isBlank() && project != null && !project.isBlank(),
        ErrorCode.VALIDATION_FAILED);
    ExecutionAccess policy = access.getIfAvailable();
    require(policy != null, ErrorCode.FORBIDDEN);
    policy.requireWrite(actor, project);
  }

  private ExecutionInputs inputPort() {
    var port = inputs.getIfAvailable();
    require(port != null, ErrorCode.FORBIDDEN);
    return port;
  }

  private static List<String> ids(List<String> values) {
    require(
        values != null
            && !values.isEmpty()
            && values.stream().allMatch(v -> v != null && !v.isBlank() && v.length() <= 64),
        ErrorCode.VALIDATION_FAILED);
    require(values.stream().distinct().count() == values.size(), ErrorCode.VALIDATION_FAILED);
    return values.stream().sorted().toList();
  }

  private static List<DeploymentTarget> select(List<DeploymentTarget> all, Set<String> ids) {
    var selected = all.stream().filter(t -> ids.contains(t.targetId())).toList();
    require(selected.size() == ids.size(), ErrorCode.NOT_FOUND);
    return selected;
  }

  private static DeploymentTarget find(List<DeploymentTarget> all, String id) {
    return all.stream()
        .filter(t -> t.id().equals(id))
        .findFirst()
        .orElseThrow(() -> new DaisyException(ErrorCode.NOT_FOUND));
  }

  private static String id(String prefix) {
    return prefix + "_" + UUID.randomUUID();
  }

  private static void require(boolean condition, ErrorCode code) {
    if (!condition) throw new DaisyException(code);
  }

  private ObjectNode payload(Deployment deployment) {
    return mapper
        .createObjectNode()
        .put("deployment_id", deployment.id())
        .put("status", deployment.status().code());
  }

  private ObjectNode payload(Deployment deployment, DeploymentTarget target) {
    return payload(deployment)
        .put("deployment_target_id", target.id())
        .put("target_id", target.targetId())
        .put("status", target.status().code())
        .put("attempt", target.attempt());
  }

  private IdempotencyService.Response response(Deployment deployment, int status) {
    return new IdempotencyService.Response(status, payload(deployment));
  }

  private DeploymentEvent event(
      String source,
      String sourceId,
      Long sequence,
      String execution,
      String target,
      String type,
      ObjectNode payload,
      String processing,
      Instant at) {
    return new DeploymentEvent(
        source,
        sourceId,
        sequence,
        execution,
        target,
        type,
        null,
        null,
        "info",
        null,
        payload,
        processing,
        null,
        null,
        null,
        at);
  }

  private String internal(
      Deployment deployment,
      DeploymentTarget target,
      String execution,
      String type,
      ObjectNode payload,
      String reason,
      Instant now) {
    String eventId = UUID.randomUUID().toString();
    if (reason != null) payload.put("reason", reason);
    journal.appendDeployment(
        deployment.projectId(),
        deployment.id(),
        event(
            "backend",
            eventId,
            null,
            execution,
            target == null ? null : target.id(),
            type,
            payload,
            "applied",
            now),
        true);
    return eventId;
  }

  private void stateEvent(Deployment deployment, Instant now) {
    internal(
        deployment,
        null,
        null,
        deployment.status().terminal() ? "deployment.completed" : "deployment.state_changed",
        payload(deployment),
        null,
        now);
  }
}
