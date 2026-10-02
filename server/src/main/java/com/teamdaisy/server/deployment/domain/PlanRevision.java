package com.teamdaisy.server.deployment.domain;

import com.fasterxml.jackson.databind.JsonNode;
import com.teamdaisy.server.common.json.CanonicalJson;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import jakarta.persistence.UniqueConstraint;
import java.time.Instant;
import org.hibernate.annotations.JdbcTypeCode;
import org.hibernate.type.SqlTypes;

@Entity
@Table(
    name = "plan_revision",
    uniqueConstraints = {
      @UniqueConstraint(columnNames = {"id", "deployment_target_id"}),
      @UniqueConstraint(columnNames = {"deployment_target_id", "revision"}),
      @UniqueConstraint(columnNames = {"source", "source_plan_id"})
    })
public class PlanRevision {
  @Id
  @Column(name = "id", nullable = false, length = 64)
  private String id;

  @Column(name = "deployment_target_id", nullable = false, length = 64)
  private String deploymentTargetId;

  @Column(name = "execution_id", nullable = false, length = 64)
  private String executionId;

  @Column(name = "project_id", nullable = false, length = 64)
  private String projectId;

  @Column(name = "target_id", nullable = false, length = 64)
  private String targetId;

  @Column(name = "revision", nullable = false)
  private int revision;

  @Column(name = "source", nullable = false, length = 512)
  private String source;

  @Column(name = "source_plan_id", nullable = false, length = 255)
  private String sourcePlanId;

  @Column(name = "input_hash", nullable = false, length = 128)
  private String inputHash;

  @Column(name = "script_id", nullable = false, length = 64)
  private String scriptId;

  @Column(name = "artifact_ref", nullable = false, columnDefinition = "text")
  private String artifactRef;

  @Column(name = "digest", nullable = false, length = 128)
  private String digest;

  @JdbcTypeCode(SqlTypes.JSON)
  @Column(name = "summary", nullable = false, columnDefinition = "jsonb")
  private JsonNode summary;

  @JdbcTypeCode(SqlTypes.JSON)
  @Column(name = "resources", nullable = false, columnDefinition = "jsonb")
  private JsonNode resources;

  @Column(name = "state", nullable = false, length = 32)
  private String state;

  @Column(name = "created_at", nullable = false, columnDefinition = "timestamptz")
  private Instant createdAt;

  @Column(name = "expires_at", nullable = false, columnDefinition = "timestamptz")
  private Instant expiresAt;

  @Column(name = "invalidated_at", nullable = true, columnDefinition = "timestamptz")
  private Instant invalidatedAt;

  @Column(name = "invalidation_reason", nullable = true, length = 255)
  private String invalidationReason;

  @Column(name = "artifact_expires_at", nullable = true, columnDefinition = "timestamptz")
  private Instant artifactExpiresAt;

  protected PlanRevision() {}

  public static PlanRevision create(
      String id,
      String deploymentTargetId,
      String executionId,
      String projectId,
      String targetId,
      int revision,
      String source,
      String sourcePlanId,
      String inputHash,
      String scriptId,
      String artifactRef,
      String digest,
      JsonNode summary,
      JsonNode resources,
      Instant now,
      Instant expiry,
      Instant artifactExpiry) {
    var value = new PlanRevision();
    value.id = DomainChecks.id(id);
    value.deploymentTargetId = DomainChecks.id(deploymentTargetId);
    value.executionId = DomainChecks.id(executionId);
    value.projectId = DomainChecks.id(projectId);
    value.targetId = DomainChecks.id(targetId);
    if (revision < 1) DomainChecks.invalid();
    value.revision = revision;
    value.source = DomainChecks.text(source, 512);
    value.sourcePlanId = DomainChecks.text(sourcePlanId, 255);
    value.inputHash = DomainChecks.hash(inputHash);
    value.scriptId = DomainChecks.id(scriptId);
    value.artifactRef = DomainChecks.safeText(artifactRef, 4096);
    if (artifactRef.contains("?") || artifactRef.contains("#") || artifactRef.contains("@"))
      DomainChecks.invalid();
    value.digest = DomainChecks.hash(digest);
    value.summary = DomainChecks.object(summary);
    validateSummary(summary);
    if (resources == null || !resources.isArray()) DomainChecks.invalid();
    for (JsonNode resource : resources) {
      if (!resource.isObject()) DomainChecks.invalid();
      DomainChecks.keys(resource, java.util.Set.of("address", "actions"));
      if (!resource.path("address").isTextual()) DomainChecks.invalid();
      DomainChecks.safeText(resource.path("address").asText(), 1024);
      JsonNode actions = resource.path("actions");
      if (!actions.isArray() || actions.isEmpty()) DomainChecks.invalid();
      for (JsonNode action : actions) {
        if (!action.isTextual()
            || !java.util.Set.of("create", "update", "delete", "read", "no-op")
                .contains(action.asText())) DomainChecks.invalid();
        if ("delete".equals(action.asText()) && !summary.path("has_delete").asBoolean())
          DomainChecks.invalid();
      }
    }
    value.resources = CanonicalJson.snapshot(resources);
    value.createdAt = DomainChecks.time(now);
    value.expiresAt = DomainChecks.time(expiry);
    if (!expiry.isAfter(now) || (artifactExpiry != null && artifactExpiry.isBefore(expiry)))
      DomainChecks.invalid();
    value.artifactExpiresAt = artifactExpiry;
    value.state = "active";
    return value;
  }

  private static void validateSummary(JsonNode summary) {
    DomainChecks.keys(summary, java.util.Set.of("counts", "has_delete", "risks"));
    JsonNode counts = summary.path("counts");
    DomainChecks.keys(counts, java.util.Set.of("create", "update", "delete"));
    if (!counts.isObject()
        || !summary.path("has_delete").isBoolean()
        || !summary.path("risks").isArray()) DomainChecks.invalid();
    for (String name : java.util.List.of("create", "update", "delete")) {
      JsonNode count = counts.path(name);
      if (!count.isIntegralNumber() || !count.canConvertToInt() || count.asInt() < 0)
        DomainChecks.invalid();
    }
    if (summary.path("has_delete").asBoolean() != (counts.path("delete").asInt() > 0))
      DomainChecks.invalid();
    for (JsonNode risk : summary.path("risks")) {
      DomainChecks.keys(risk, java.util.Set.of("level", "rule", "resource", "message"));
      if (!risk.isObject() || !risk.path("level").isTextual()) DomainChecks.invalid();
      DomainChecks.safeText(risk.path("level").asText(), 32);
      for (String field : java.util.List.of("rule", "resource", "message")) {
        if (!risk.path(field).isTextual()) DomainChecks.invalid();
        DomainChecks.safeText(risk.path(field).asText(), field.equals("message") ? 4096 : 1024);
      }
    }
  }

  public void assertUsable(
      String expectedId, String expectedDigest, String expectedInputHash, Instant now) {
    DomainChecks.time(now);
    DomainChecks.require(
        "active".equals(state)
            && id.equals(expectedId)
            && digest.equals(expectedDigest)
            && inputHash.equals(expectedInputHash)
            && now.isBefore(expiresAt)
            && (artifactExpiresAt == null || now.isBefore(artifactExpiresAt)));
  }

  public void invalidate(String reason, Instant now) {
    DomainChecks.text(reason, 255);
    DomainChecks.time(now);
    if (!"active".equals(state)) return;
    state = "expired".equals(reason) ? "expired" : "superseded";
    invalidatedAt = now;
    invalidationReason = reason;
  }

  public boolean hasDelete() {
    return summary.path("has_delete").asBoolean();
  }

  public String id() {
    return id;
  }

  public String deploymentTargetId() {
    return deploymentTargetId;
  }

  public String executionId() {
    return executionId;
  }

  public String projectId() {
    return projectId;
  }

  public String targetId() {
    return targetId;
  }

  public int revision() {
    return revision;
  }

  public String source() {
    return source;
  }

  public String sourcePlanId() {
    return sourcePlanId;
  }

  public String inputHash() {
    return inputHash;
  }

  public String scriptId() {
    return scriptId;
  }

  public String artifactRef() {
    return artifactRef;
  }

  public String digest() {
    return digest;
  }

  public JsonNode summary() {
    return summary.deepCopy();
  }

  public JsonNode resources() {
    return resources.deepCopy();
  }

  public String state() {
    return state;
  }

  public Instant createdAt() {
    return createdAt;
  }

  public Instant expiresAt() {
    return expiresAt;
  }

  public Instant artifactExpiresAt() {
    return artifactExpiresAt;
  }

  public Instant invalidatedAt() {
    return invalidatedAt;
  }

  public String invalidationReason() {
    return invalidationReason;
  }
}
