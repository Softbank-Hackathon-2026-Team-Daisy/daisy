package com.teamdaisy.server.jenkins.application;

import com.fasterxml.jackson.core.JsonParser;
import com.fasterxml.jackson.databind.DeserializationFeature;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.MapperFeature;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.PropertyNamingStrategies;
import com.teamdaisy.server.ai.application.AiUsageService;
import com.teamdaisy.server.common.error.DaisyException;
import com.teamdaisy.server.common.error.ErrorCode;
import com.teamdaisy.server.common.json.CanonicalJson;
import com.teamdaisy.server.deployment.application.DeploymentExecutionService;
import com.teamdaisy.server.deployment.domain.DeploymentTargetStatus;
import com.teamdaisy.server.history.application.JenkinsReceiptService;
import com.teamdaisy.server.jenkins.application.ExecutionCallbackAccess.VerifiedSender;
import com.teamdaisy.server.script.application.ScriptService;
import jakarta.servlet.http.HttpServletRequest;
import java.io.IOException;
import java.math.BigDecimal;
import java.time.Instant;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class JenkinsCallbackService {
  public static final int MAX_BODY_BYTES = 256 * 1024;
  private static final Set<String> KINDS = Set.of("build", "plan", "plan_stale", "state", "script", "usage", "log", "stage");
  private final ObjectProvider<ExecutionCallbackAccess> access;
  private final JenkinsCommandService commands;
  private final DeploymentExecutionService deployments;
  private final ScriptService scripts;
  private final AiUsageService usage;
  private final JenkinsReceiptService history;
  private final ObjectMapper mapper;
  private final CanonicalJson json;

  public JenkinsCallbackService(ObjectProvider<ExecutionCallbackAccess> access, JenkinsCommandService commands,
      DeploymentExecutionService deployments, ScriptService scripts, AiUsageService usage,
      JenkinsReceiptService history, ObjectMapper mapper, CanonicalJson json) {
    this.access = access; this.commands = commands; this.deployments = deployments; this.scripts = scripts;
    this.usage = usage; this.history = history; this.json = json;
    this.mapper = mapper.copy().setPropertyNamingStrategy(PropertyNamingStrategies.SNAKE_CASE)
        .enable(DeserializationFeature.FAIL_ON_UNKNOWN_PROPERTIES, DeserializationFeature.FAIL_ON_TRAILING_TOKENS,
            DeserializationFeature.FAIL_ON_NULL_FOR_PRIMITIVES)
        .disable(DeserializationFeature.ACCEPT_FLOAT_AS_INT)
        .disable(MapperFeature.ALLOW_COERCION_OF_SCALARS)
        .enable(JsonParser.Feature.STRICT_DUPLICATE_DETECTION);
  }

  public record Envelope(String executionId, String requestId, String jobFullName, Long buildNumber,
      Long queueId, String externalEventId, Long sourceSequence, Instant occurredAt,
      String deploymentTargetId, String kind, JsonNode payload) {}
  public record Receipt(String executionId, String externalEventId, String receiptId) {}
  public record Build(String sourceVersionId, String commitSha, JsonNode imageRefs) {}
  public record Plan(String sourcePlanId, String inputHash, String scriptId, Boolean reusedScript, Integer attempt,
      String artifactRef, String digest, JsonNode summary, JsonNode resources, Instant expiresAt, Instant artifactExpiresAt) {}
  public record State(String status, Integer attempt, String errorSummary, JsonNode result) {}
  public record Stale(String planId, String planDigest, String inputHash, Boolean confirmedNotApplied, Boolean executionTerminated) {}
  public record Script(String artifactRef, String contentDigest, String compatibilityKey, JsonNode metadata,
      Instant validatedAt, Instant artifactExpiresAt) {}
  public record Usage(String provider, String model, String step, Integer attempt, String status,
      Long inputTokens, Long outputTokens, JsonNode usageDetails, BigDecimal costUsd, String costBasis) {}
  public record Log(String level, String step, String message, String streamId, Long offset, Long endOffset) {}
  public record Stage(String stageOccurrenceId, String step, String phase, String level, String message) {}

  public VerifiedSender authenticate(HttpServletRequest request) {
    var policy = access.getIfAvailable();
    require(policy != null, ErrorCode.FORBIDDEN);
    var sender = policy.verify(request);
    require(sender != null && sender.instanceId() != null && !sender.instanceId().isBlank()
        && sender.instanceId().length() <= 128 && !sender.permittedJobs().isEmpty(), ErrorCode.FORBIDDEN);
    return sender;
  }

  public Envelope read(HttpServletRequest request) {
    require(request.getContentLengthLong() <= MAX_BODY_BYTES, ErrorCode.VALIDATION_FAILED);
    try {
      byte[] body = request.getInputStream().readNBytes(MAX_BODY_BYTES + 1);
      require(body.length <= MAX_BODY_BYTES, ErrorCode.VALIDATION_FAILED);
      return mapper.readValue(body, Envelope.class);
    } catch (IOException error) { throw new DaisyException(ErrorCode.VALIDATION_FAILED); }
  }

  @Transactional
  public Receipt receive(VerifiedSender sender, Envelope e) {
    validate(e);
    require(sender != null && sender.instanceId() != null && sender.permittedJobs().contains(e.jobFullName()), ErrorCode.FORBIDDEN);
    // Parsing each content record before binding makes malformed payloads fail without storage changes.
    Object content = switch (e.kind()) {
      case "build" -> content(e.payload(), Build.class);
      case "plan" -> content(e.payload(), Plan.class);
      case "plan_stale" -> content(e.payload(), Stale.class);
      case "state" -> content(e.payload(), State.class);
      case "script" -> content(e.payload(), Script.class);
      case "usage" -> content(e.payload(), Usage.class);
      case "log" -> content(e.payload(), Log.class);
      case "stage" -> content(e.payload(), Stage.class);
      default -> throw new DaisyException(ErrorCode.VALIDATION_FAILED);
    };
    var scope = commands.bindCallback(e.executionId(), e.requestId(), sender.instanceId(), e.jobFullName(),
        e.queueId(), e.buildNumber(), e.deploymentTargetId());
    String source = "jenkins:" + json.hash(mapper.valueToTree(Map.of("instance", sender.instanceId(),
        "job", e.jobFullName(), "build", e.buildNumber(), "target", e.deploymentTargetId() == null ? "" : e.deploymentTargetId())));
    String id = e.externalEventId();
    switch (e.kind()) {
      case "build" -> {
        Build p = (Build) content;
        text(p.sourceVersionId(), 64); text(p.commitSha(), 64);
        require(p.imageRefs() != null && p.imageRefs().isObject(), ErrorCode.VALIDATION_FAILED);
        deployments.bindBuildResult(new DeploymentExecutionService.BuildResult(scope.projectId(), scope.deploymentId(), scope.id(),
            source, id, p.sourceVersionId(), p.commitSha(), p.imageRefs(), e.occurredAt()));
      }
      case "plan" -> {
        Plan p = (Plan) content;
        text(p.sourcePlanId(), 255); text(p.inputHash(), 128); text(p.scriptId(), 64);
        text(p.artifactRef(), 4096); text(p.digest(), 128);
        require(p.summary() != null && p.summary().isObject() && p.resources() != null && p.resources().isArray()
            && p.expiresAt() != null && p.reusedScript() != null && p.attempt() != null, ErrorCode.VALIDATION_FAILED);
        time(p.expiresAt()); if (p.artifactExpiresAt() != null) time(p.artifactExpiresAt());
        deployments.acceptPlan(new DeploymentExecutionService.PlanResult(scope.projectId(), scope.deploymentId(), scope.id(), e.deploymentTargetId(),
            source, id, e.sourceSequence(), p.sourcePlanId(), p.inputHash(), p.scriptId(), p.reusedScript(), p.attempt(), p.artifactRef(), p.digest(),
            p.summary(), p.resources(), p.expiresAt(), p.artifactExpiresAt(), e.occurredAt()));
      }
      case "state" -> {
        State p = (State) content;
        require(p.attempt() != null, ErrorCode.VALIDATION_FAILED);
        DeploymentTargetStatus status;
        try { status = DeploymentTargetStatus.valueOf(p.status().toUpperCase(Locale.ROOT)); }
        catch (IllegalArgumentException | NullPointerException error) { throw new DaisyException(ErrorCode.VALIDATION_FAILED); }
        require(status.code().equals(p.status()), ErrorCode.VALIDATION_FAILED);
        deployments.acceptState(new DeploymentExecutionService.StateResult(scope.projectId(), scope.deploymentId(), scope.id(), e.deploymentTargetId(),
            source, id, e.sourceSequence(), status, p.attempt(), p.errorSummary(), p.result(), e.occurredAt()));
      }
      case "plan_stale" -> {
        Stale p = (Stale) content;
        text(p.planId(), 64); text(p.planDigest(), 128); text(p.inputHash(), 128);
        require(p.confirmedNotApplied() != null && p.executionTerminated() != null, ErrorCode.VALIDATION_FAILED);
        deployments.acceptStale(new DeploymentExecutionService.StaleResult(scope.projectId(), scope.deploymentId(), scope.id(), e.deploymentTargetId(),
            source, id, e.sourceSequence(), p.planId(), p.planDigest(), p.inputHash(), p.confirmedNotApplied(), p.executionTerminated(), e.occurredAt()));
      }
      case "script" -> {
        Script p = (Script) content;
        time(p.validatedAt()); if (p.artifactExpiresAt() != null) time(p.artifactExpiresAt());
        id = scripts.receive(scope.id(), scope.deploymentId(), e.deploymentTargetId(), new ScriptService.ScriptInput(source,
            id, p.artifactRef(), p.contentDigest(), p.compatibilityKey(), p.metadata(), p.validatedAt(), p.artifactExpiresAt())).id();
      }
      case "usage" -> {
        Usage p = (Usage) content;
        require(p.attempt() != null, ErrorCode.VALIDATION_FAILED);
        id = usage.receive(scope.id(), scope.deploymentId(), e.deploymentTargetId(), new AiUsageService.UsageInput(source, id,
            p.provider(), p.model(), p.step(), p.attempt(), p.status(), p.inputTokens(), p.outputTokens(), p.usageDetails(), p.costUsd(),
            p.costBasis(), e.occurredAt())).id();
      }
      case "log" -> id = Long.toString(history.log(scope, source, e.externalEventId(), e.sourceSequence(), e.deploymentTargetId(),
          (Log) content, json.hash(mapper.valueToTree(e)), e.occurredAt()).id());
      case "stage" -> id = Long.toString(history.stage(scope, source, e.externalEventId(), e.sourceSequence(), e.deploymentTargetId(),
          (Stage) content, json.hash(mapper.valueToTree(e)), e.occurredAt()).id());
      default -> throw new DaisyException(ErrorCode.VALIDATION_FAILED);
    }
    return new Receipt(scope.id(), e.externalEventId(), id);
  }

  private <T> T content(JsonNode node, Class<T> type) {
    try { return mapper.treeToValue(node, type); }
    catch (IOException | IllegalArgumentException error) { throw new DaisyException(ErrorCode.VALIDATION_FAILED); }
  }

  private static void validate(Envelope e) {
    require(e != null && e.kind() != null && KINDS.contains(e.kind()), ErrorCode.VALIDATION_FAILED);
    text(e.executionId(), 64); text(e.requestId(), 255); text(e.jobFullName(), 512); text(e.externalEventId(), 255);
    require(e.buildNumber() != null && e.buildNumber() > 0 && (e.queueId() == null || e.queueId() > 0)
        && e.occurredAt() != null
        && e.payload() != null && e.payload().isObject(), ErrorCode.VALIDATION_FAILED);
    time(e.occurredAt());
    if (e.kind().equals("build")) require(e.deploymentTargetId() == null && e.sourceSequence() == null, ErrorCode.VALIDATION_FAILED);
    else if (!e.kind().equals("log") || e.deploymentTargetId() != null) text(e.deploymentTargetId(), 64);
    if (Set.of("plan", "plan_stale", "state", "log", "stage").contains(e.kind()))
      require(e.sourceSequence() != null && e.sourceSequence() >= 0, ErrorCode.VALIDATION_FAILED);
    else require(e.sourceSequence() == null, ErrorCode.VALIDATION_FAILED);
  }
  private static void text(String value, int max) { require(value != null && !value.isBlank() && value.length() <= max, ErrorCode.VALIDATION_FAILED); }
  private static void time(Instant value) { require(value != null && value.compareTo(Instant.EPOCH) >= 0
      && value.isBefore(Instant.parse("+10000-01-01T00:00:00Z")), ErrorCode.VALIDATION_FAILED); }
  private static void require(boolean value, ErrorCode code) { if (!value) throw new DaisyException(code); }
}
