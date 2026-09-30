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
import java.util.List;
import java.util.Objects;
import org.hibernate.annotations.DynamicUpdate;
import org.hibernate.annotations.JdbcTypeCode;
import org.hibernate.type.SqlTypes;

@Entity
@DynamicUpdate
@Table(
    name = "deployment",
    uniqueConstraints = {@UniqueConstraint(columnNames = {"id", "project_id"})})
public class Deployment {
  @Id
  @Column(name = "id", nullable = false, length = 64)
  private String id;

  @Column(name = "project_id", nullable = false, length = 64)
  private String projectId;

  @Column(name = "source_version_id", nullable = true, length = 64)
  private String sourceVersionId;

  @Column(name = "requested_by", nullable = false, length = 64)
  private String requestedBy;

  @Column(name = "kind", nullable = false, length = 32)
  private String kind;

  @Column(name = "retry_of_deployment_id", nullable = true, length = 64)
  private String retryOfDeploymentId;

  @Column(name = "rollback_of_deployment_id", nullable = true, length = 64)
  private String rollbackOfDeploymentId;

  @Column(name = "rollback_trigger_deployment_id", nullable = true, length = 64)
  private String rollbackTriggerDeploymentId;

  @Column(name = "commit_sha", nullable = false, length = 64)
  private String commitSha;

  @JdbcTypeCode(SqlTypes.JSON)
  @Column(name = "repository_snapshot", nullable = false, columnDefinition = "jsonb")
  private JsonNode repositorySnapshot;

  @JdbcTypeCode(SqlTypes.JSON)
  @Column(name = "input_snapshot", nullable = false, columnDefinition = "jsonb")
  private JsonNode inputSnapshot;

  @Column(name = "request_hash", nullable = false, length = 128)
  private String requestHash;

  @JdbcTypeCode(SqlTypes.JSON)
  @Column(name = "image_refs", nullable = true, columnDefinition = "jsonb")
  private JsonNode imageRefs;

  @Column(name = "resolved_input_hash", nullable = true, length = 128)
  private String resolvedInputHash;

  @Convert(converter = DeploymentStatus.Converter.class)
  @Column(name = "status", nullable = false, length = 32)
  private DeploymentStatus status;

  @Column(name = "last_event_seq", nullable = false)
  private long lastEventSeq;

  @Version
  @Column(name = "version", nullable = false)
  private long version;

  @Column(name = "created_at", nullable = false, columnDefinition = "timestamptz")
  private Instant createdAt;

  @Column(name = "started_at", nullable = true, columnDefinition = "timestamptz")
  private Instant startedAt;

  @Column(name = "finished_at", nullable = true, columnDefinition = "timestamptz")
  private Instant finishedAt;

  protected Deployment() {}

  public static Deployment create(String id, String projectId, String actor, String commit,
      JsonNode repository, JsonNode input, String requestHash, Instant now) {
    var value = new Deployment();
    value.id = DomainChecks.id(id);
    value.projectId = DomainChecks.id(projectId);
    value.requestedBy = DomainChecks.id(actor);
    if (commit == null || !commit.matches("[0-9a-f]{40}|[0-9a-f]{64}")) DomainChecks.invalid();
    value.commitSha = commit;
    value.repositorySnapshot = DomainChecks.object(repository);
    value.inputSnapshot = DomainChecks.object(input);
    if (!input.path("hash_format_version").isIntegralNumber()
        || input.path("hash_format_version").asInt() != 1) DomainChecks.invalid();
    value.requestHash = DomainChecks.hash(requestHash);
    value.createdAt = DomainChecks.time(now);
    value.kind = "normal";
    value.status = DeploymentStatus.QUEUED;
    return value;
  }

  public static Deployment retry(String id, String actor, Deployment original,
      String requestHash, Instant now) {
    DomainChecks.require(original.status.terminal() && original.status != DeploymentStatus.SUCCEEDED
        && original.status != DeploymentStatus.CANCELLED && !original.id.equals(id));
    var value = copyRequest(id, actor, original, requestHash, now);
    value.kind = "retry";
    value.retryOfDeploymentId = original.id;
    return value;
  }

  public static Deployment rollback(String id, String actor, Deployment original,
      String triggerId, String requestHash, Instant now) {
    DomainChecks.require(original.status == DeploymentStatus.SUCCEEDED && !original.id.equals(id));
    if (triggerId != null) {
      DomainChecks.id(triggerId);
      DomainChecks.require(!triggerId.equals(id));
    }
    var value = copyRequest(id, actor, original, requestHash, now);
    DomainChecks.require(value.sourceVersionId != null && value.imageRefs != null);
    value.kind = "rollback";
    value.rollbackOfDeploymentId = original.id;
    value.rollbackTriggerDeploymentId = triggerId;
    return value;
  }

  private static Deployment copyRequest(String id, String actor, Deployment original,
      String requestHash, Instant now) {
    var value = create(id, original.projectId, actor, original.commitSha,
        original.repositorySnapshot, original.inputSnapshot, requestHash, now);
    if (original.sourceVersionId != null) value.bindSource(original.sourceVersionId,
        original.commitSha, original.imageRefs, original.resolvedInputHash);
    return value;
  }

  public void bindSource(String sourceId, String commit, JsonNode images, String resolvedHash) {
    DomainChecks.id(sourceId);
    DomainChecks.hash(resolvedHash);
    JsonNode copy = DomainChecks.object(images);
    if (copy.isEmpty()) DomainChecks.invalid();
    for (JsonNode image : copy) {
      if (!image.isObject() || !image.path("commit_sha").asText().equals(commit)
          || !image.path("image_ref").isTextual() || image.path("image_ref").asText().isBlank())
        DomainChecks.invalid();
      if (image.has("digest") && !image.path("digest").isNull())
        DomainChecks.hash(image.path("digest").asText());
      else if (!image.path("image_ref").asText().endsWith(":" + commit)) DomainChecks.invalid();
    }
    DomainChecks.require(commitSha.equals(commit));
    if (sourceVersionId != null) {
      DomainChecks.require(sourceVersionId.equals(sourceId) && imageRefs.equals(copy)
          && resolvedInputHash.equals(resolvedHash));
      return;
    }
    DomainChecks.require(!status.terminal());
    sourceVersionId = sourceId;
    imageRefs = copy;
    resolvedInputHash = resolvedHash;
  }

  public void markStarted(Instant now) {
    DomainChecks.time(now);
    DomainChecks.require(!status.terminal() && !now.isBefore(createdAt));
    if (startedAt == null) startedAt = now;
    if (status == DeploymentStatus.QUEUED) status = DeploymentStatus.RUNNING;
  }

  public void aggregate(List<DeploymentTarget> targets, Instant now) {
    DomainChecks.time(now);
    if (targets == null || targets.isEmpty()) DomainChecks.invalid();
    DomainChecks.require(targets.stream().allMatch(t -> id.equals(t.deploymentId())));
    DeploymentStatus next;
    if (targets.stream().anyMatch(t -> t.status().running())) next = DeploymentStatus.RUNNING;
    else if (targets.stream().anyMatch(t -> t.status() == DeploymentTargetStatus.AWAITING_APPROVAL))
      next = DeploymentStatus.AWAITING_APPROVAL;
    else if (targets.stream().allMatch(t -> t.status().terminal())) {
      long successes = targets.stream().filter(t -> t.status() == DeploymentTargetStatus.SUCCEEDED).count();
      next = successes == targets.size() ? DeploymentStatus.SUCCEEDED
          : successes > 0 ? DeploymentStatus.PARTIALLY_SUCCEEDED
          : targets.stream().anyMatch(t -> t.status() == DeploymentTargetStatus.FAILED)
              ? DeploymentStatus.FAILED : DeploymentStatus.CANCELLED;
    } else next = startedAt == null && targets.stream().allMatch(t -> t.status() == DeploymentTargetStatus.WAITING)
        ? DeploymentStatus.QUEUED : DeploymentStatus.RUNNING;
    DomainChecks.require(!status.terminal() || status == next);
    status = next;
    if (next.terminal() && finishedAt == null) finishedAt = now;
    if (startedAt == null && targets.stream().anyMatch(t -> t.startedAt() != null))
      startedAt = targets.stream().map(DeploymentTarget::startedAt).filter(Objects::nonNull)
          .min(Instant::compareTo).orElse(now);
  }

  public String id() { return id; }
  public String projectId() { return projectId; }
  public String sourceVersionId() { return sourceVersionId; }
  public String requestedBy() { return requestedBy; }
  public String kind() { return kind; }
  public String retryOfDeploymentId() { return retryOfDeploymentId; }
  public String rollbackOfDeploymentId() { return rollbackOfDeploymentId; }
  public String rollbackTriggerDeploymentId() { return rollbackTriggerDeploymentId; }
  public String commitSha() { return commitSha; }
  public JsonNode repositorySnapshot() { return repositorySnapshot.deepCopy(); }
  public JsonNode inputSnapshot() { return inputSnapshot.deepCopy(); }
  public JsonNode imageRefs() { return imageRefs == null ? null : imageRefs.deepCopy(); }
  public String requestHash() { return requestHash; }
  public String resolvedInputHash() { return resolvedInputHash; }
  public DeploymentStatus status() { return status; }
  public Instant createdAt() { return createdAt; }
  public Instant startedAt() { return startedAt; }
  public Instant finishedAt() { return finishedAt; }
  public long lastEventSeq() { return lastEventSeq; }
}
