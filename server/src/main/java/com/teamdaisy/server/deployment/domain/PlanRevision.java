package com.teamdaisy.server.deployment.domain;

import com.fasterxml.jackson.databind.JsonNode;
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
}
