package com.teamdaisy.server.deployment.domain;

import com.fasterxml.jackson.databind.JsonNode;
import jakarta.persistence.Column;
import jakarta.persistence.Convert;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import jakarta.persistence.UniqueConstraint;
import jakarta.persistence.Version;
import java.time.Instant;
import org.hibernate.annotations.DynamicUpdate;
import org.hibernate.annotations.JdbcTypeCode;
import org.hibernate.type.SqlTypes;

@Entity
@DynamicUpdate
@Table(
    name = "deployment_target",
    uniqueConstraints = {
      @UniqueConstraint(columnNames = {"deployment_id", "target_id"}),
      @UniqueConstraint(columnNames = {"id", "deployment_id"}),
      @UniqueConstraint(columnNames = {"id", "target_id", "project_id"}),
      @UniqueConstraint(columnNames = {"id", "project_id"}),
      @UniqueConstraint(columnNames = {"deployment_id", "state_identity"})
    })
public class DeploymentTarget {
  @Id
  @Column(name = "id", nullable = false, length = 64)
  private String id;

  @Column(name = "deployment_id", nullable = false, length = 64)
  private String deploymentId;

  @Column(name = "project_id", nullable = false, length = 64)
  private String projectId;

  @Column(name = "target_id", nullable = false, length = 64)
  private String targetId;

  @JdbcTypeCode(SqlTypes.JSON)
  @Column(name = "target_snapshot", nullable = false, columnDefinition = "jsonb")
  private JsonNode targetSnapshot;

  @Column(name = "retry_of_deployment_target_id", nullable = true, length = 64)
  private String retryOfDeploymentTargetId;

  @Column(name = "restored_from_deployment_target_id", nullable = true, length = 64)
  private String restoredFromDeploymentTargetId;

  @Column(name = "state_identity", nullable = false, length = 512)
  private String stateIdentity;

  @Column(name = "input_hash", nullable = true, length = 128)
  private String inputHash;

  @Convert(converter = DeploymentTargetStatus.Converter.class)
  @Column(name = "status", nullable = false, length = 32)
  private DeploymentTargetStatus status;

  @Column(name = "attempt", nullable = false)
  private short attempt;

  @Column(name = "ai_reused", nullable = false)
  private boolean aiReused;

  @Column(name = "script_id", nullable = true, length = 64)
  private String scriptId;

  @Column(name = "current_plan_id", nullable = true, length = 64)
  private String currentPlanId;

  @Column(name = "current_execution_id", nullable = true, length = 64)
  private String currentExecutionId;

  @Column(name = "last_source_sequence", nullable = true)
  private Long lastSourceSequence;

  @JdbcTypeCode(SqlTypes.JSON)
  @Column(name = "result", nullable = true, columnDefinition = "jsonb")
  private JsonNode result;

  @Column(name = "error_summary", nullable = true, columnDefinition = "text")
  private String errorSummary;

  @Column(name = "cancel_requested_by", nullable = true, length = 64)
  private String cancelRequestedBy;

  @Column(name = "cancel_requested_at", nullable = true, columnDefinition = "timestamptz")
  private Instant cancelRequestedAt;

  @Column(name = "started_at", nullable = true, columnDefinition = "timestamptz")
  private Instant startedAt;

  @Column(name = "finished_at", nullable = true, columnDefinition = "timestamptz")
  private Instant finishedAt;

  @Version
  @Column(name = "version", nullable = false)
  private long version;

  protected DeploymentTarget() {}

  public static DeploymentTarget create(
      String id, Deployment deployment, String targetId, JsonNode snapshot, String stateIdentity) {
    DomainChecks.require("normal".equals(deployment.kind()));
    return newTarget(id, deployment, targetId, snapshot, stateIdentity);
  }

  private static DeploymentTarget newTarget(
      String id, Deployment deployment, String targetId, JsonNode snapshot, String stateIdentity) {
    DomainChecks.require(!deployment.status().terminal());
    var value = new DeploymentTarget();
    value.id = DomainChecks.id(id);
    value.deploymentId = deployment.id();
    value.projectId = deployment.projectId();
    value.targetId = DomainChecks.id(targetId);
    value.targetSnapshot = DomainChecks.object(snapshot);
    DomainChecks.text(snapshot.path("name").asText(), 128);
    value.stateIdentity = DomainChecks.text(stateIdentity, 512);
    value.status = DeploymentTargetStatus.WAITING;
    return value;
  }

  public static DeploymentTarget retry(
      String id, Deployment deployment, DeploymentTarget original) {
    DomainChecks.require(
        "retry".equals(deployment.kind())
            && original.deploymentId.equals(deployment.retryOfDeploymentId())
            && original.projectId.equals(deployment.projectId())
            && original.status == DeploymentTargetStatus.FAILED
            && !original.id.equals(id));
    var value =
        newTarget(
            id, deployment, original.targetId, original.targetSnapshot, original.stateIdentity);
    value.retryOfDeploymentTargetId = original.id;
    value.inputHash = original.inputHash;
    return value;
  }

  public static DeploymentTarget rollback(
      String id, Deployment deployment, DeploymentTarget original) {
    DomainChecks.require(
        "rollback".equals(deployment.kind())
            && original.deploymentId.equals(deployment.rollbackOfDeploymentId())
            && original.projectId.equals(deployment.projectId())
            && original.status == DeploymentTargetStatus.SUCCEEDED
            && !original.id.equals(id)
            && original.scriptId != null
            && original.inputHash != null
            && original.result != null);
    var value =
        newTarget(
            id, deployment, original.targetId, original.targetSnapshot, original.stateIdentity);
    value.restoredFromDeploymentTargetId = original.id;
    value.inputHash = original.inputHash;
    value.scriptId = original.scriptId;
    return value;
  }

  public void bindInput(String hash) {
    DomainChecks.hash(hash);
    DomainChecks.require(inputHash == null || inputHash.equals(hash));
    if (inputHash == null) {
      DomainChecks.require(!status.terminal());
      inputHash = hash;
    }
  }

  public void attachExecution(String executionId) {
    DomainChecks.id(executionId);
    DomainChecks.require(!status.terminal());
    if (!executionId.equals(currentExecutionId)) {
      currentExecutionId = executionId;
      lastSourceSequence = null;
    }
  }

  public boolean applyStatus(
      String executionId,
      long sequence,
      DeploymentTargetStatus next,
      int reportedAttempt,
      String error,
      JsonNode executionResult,
      Instant now) {
    DomainChecks.id(executionId);
    DomainChecks.time(now);
    if (sequence < 0 || next == null || reportedAttempt < 0 || reportedAttempt > 3)
      DomainChecks.invalid();
    if (status.terminal()
        || !executionId.equals(currentExecutionId)
        || (lastSourceSequence != null && sequence <= lastSourceSequence)) return false;
    DomainChecks.require(reportedAttempt >= attempt);
    if (next == DeploymentTargetStatus.GENERATING || next == DeploymentTargetStatus.VALIDATING) {
      DomainChecks.require(
          status != DeploymentTargetStatus.APPLYING && status != DeploymentTargetStatus.VERIFYING);
      if (next == DeploymentTargetStatus.GENERATING && reportedAttempt == 0) DomainChecks.invalid();
    }
    if (next == DeploymentTargetStatus.WAITING)
      DomainChecks.require(status == DeploymentTargetStatus.WAITING);
    if (next == DeploymentTargetStatus.AWAITING_APPROVAL)
      DomainChecks.require(currentPlanId != null);
    if (next == DeploymentTargetStatus.APPLYING)
      DomainChecks.require(
          status == DeploymentTargetStatus.AWAITING_APPROVAL
              || status == DeploymentTargetStatus.APPLYING);
    if (next == DeploymentTargetStatus.VERIFYING)
      DomainChecks.require(
          status == DeploymentTargetStatus.AWAITING_APPROVAL
              || status == DeploymentTargetStatus.APPLYING
              || status == DeploymentTargetStatus.VERIFYING);
    // The application validates immutable apply proof even when intermediate callbacks were lost.
    if (next == DeploymentTargetStatus.SUCCEEDED)
      DomainChecks.require(
          status == DeploymentTargetStatus.AWAITING_APPROVAL
              || status == DeploymentTargetStatus.APPLYING
              || status == DeploymentTargetStatus.VERIFYING);
    if (next == DeploymentTargetStatus.APPLYING
        || next == DeploymentTargetStatus.VERIFYING
        || next == DeploymentTargetStatus.SUCCEEDED) DomainChecks.require(currentPlanId != null);
    JsonNode resultCopy = executionResult == null ? null : DomainChecks.object(executionResult);
    if (next == DeploymentTargetStatus.SUCCEEDED)
      DomainChecks.require(resultCopy != null && !resultCopy.isEmpty());
    if (error != null && error.length() > 16384) DomainChecks.invalid();
    status = next;
    attempt = (short) reportedAttempt;
    lastSourceSequence = sequence;
    errorSummary = error;
    if (resultCopy != null) result = resultCopy;
    if (startedAt == null && next != DeploymentTargetStatus.WAITING) startedAt = now;
    if (next.terminal()) finishedAt = now;
    return true;
  }

  public void adoptPlan(PlanRevision plan, Instant now) {
    DomainChecks.require(
        !status.terminal()
            && id.equals(plan.deploymentTargetId())
            && status != DeploymentTargetStatus.APPLYING
            && status != DeploymentTargetStatus.VERIFYING
            && projectId.equals(plan.projectId())
            && targetId.equals(plan.targetId())
            && plan.executionId().equals(currentExecutionId));
    plan.assertUsable(plan.id(), plan.digest(), inputHash, now);
    currentPlanId = plan.id();
    scriptId = plan.scriptId();
    status = DeploymentTargetStatus.AWAITING_APPROVAL;
  }

  public void clearPlanForReplan(Instant now) {
    DomainChecks.time(now);
    DomainChecks.require(!status.terminal());
    currentPlanId = null;
    status = DeploymentTargetStatus.VALIDATING;
  }

  public void clearCurrentPlan(String expectedPlanId) {
    DomainChecks.require(expectedPlanId != null && expectedPlanId.equals(currentPlanId));
    currentPlanId = null;
  }

  public void recordReuse(boolean reused, boolean hasAiUsage) {
    DomainChecks.require(!reused || !hasAiUsage);
    aiReused = reused;
  }

  public void requestCancellation(String actor, Instant now) {
    DomainChecks.id(actor);
    DomainChecks.time(now);
    DomainChecks.require(!status.terminal());
    if (cancelRequestedAt == null) {
      cancelRequestedBy = actor;
      cancelRequestedAt = now;
    }
  }

  /** Called only after the application layer has confirmed no execution remains active. */
  public void confirmCancellation(Instant now) {
    DomainChecks.time(now);
    DomainChecks.require(!status.terminal());
    status = DeploymentTargetStatus.CANCELLED;
    finishedAt = now;
  }

  public String id() {
    return id;
  }

  public String deploymentId() {
    return deploymentId;
  }

  public String projectId() {
    return projectId;
  }

  public String targetId() {
    return targetId;
  }

  public JsonNode targetSnapshot() {
    return targetSnapshot.deepCopy();
  }

  public String stateIdentity() {
    return stateIdentity;
  }

  public String inputHash() {
    return inputHash;
  }

  public DeploymentTargetStatus status() {
    return status;
  }

  public int attempt() {
    return attempt;
  }

  public boolean aiReused() {
    return aiReused;
  }

  public String scriptId() {
    return scriptId;
  }

  public String currentPlanId() {
    return currentPlanId;
  }

  public String currentExecutionId() {
    return currentExecutionId;
  }

  public Long lastSourceSequence() {
    return lastSourceSequence;
  }

  public JsonNode result() {
    return result == null ? null : result.deepCopy();
  }

  public String errorSummary() {
    return errorSummary;
  }

  public String cancelRequestedBy() {
    return cancelRequestedBy;
  }

  public Instant cancelRequestedAt() {
    return cancelRequestedAt;
  }

  public Instant startedAt() {
    return startedAt;
  }

  public Instant finishedAt() {
    return finishedAt;
  }

  public String retryOfDeploymentTargetId() {
    return retryOfDeploymentTargetId;
  }

  public String restoredFromDeploymentTargetId() {
    return restoredFromDeploymentTargetId;
  }
}
