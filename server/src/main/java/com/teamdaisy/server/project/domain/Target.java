package com.teamdaisy.server.project.domain;

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
    name = "target",
    uniqueConstraints = {@UniqueConstraint(columnNames = {"id", "project_id"})})
public class Target {
  @Id
  @Column(name = "id", nullable = false, length = 64)
  private String id;

  @Column(name = "project_id", nullable = false, length = 64)
  private String projectId;

  @Column(name = "name", nullable = false, length = 128)
  private String name;

  @Column(name = "environment_type", nullable = false, length = 32)
  private String environmentType;

  @Column(name = "state_identity", nullable = false, length = 512)
  private String stateIdentity;

  @JdbcTypeCode(SqlTypes.JSON)
  @Column(name = "config", nullable = false, columnDefinition = "jsonb")
  private JsonNode config;

  @Column(name = "config_revision", nullable = false)
  private long configRevision;

  @Column(name = "credential_ref", nullable = true, columnDefinition = "text")
  private String credentialRef;

  @Column(name = "credential_version", nullable = true, length = 255)
  private String credentialVersion;

  @Column(name = "connection_state", nullable = false, length = 32)
  private String connectionState;

  @Column(name = "connection_checked_at", nullable = true, columnDefinition = "timestamptz")
  private Instant connectionCheckedAt;

  @Column(name = "current_deployment_target_id", nullable = true, length = 64)
  private String currentDeploymentTargetId;

  @JdbcTypeCode(SqlTypes.JSON)
  @Column(name = "observed_state", nullable = true, columnDefinition = "jsonb")
  private JsonNode observedState;

  @Column(name = "observed_at", nullable = true, columnDefinition = "timestamptz")
  private Instant observedAt;

  @JdbcTypeCode(SqlTypes.JSON)
  @Column(name = "reuse_assessment", nullable = true, columnDefinition = "jsonb")
  private JsonNode reuseAssessment;

  @Column(name = "created_at", nullable = false, columnDefinition = "timestamptz")
  private Instant createdAt;

  @Column(name = "updated_at", nullable = false, columnDefinition = "timestamptz")
  private Instant updatedAt;

  @Column(name = "archived_at", nullable = true, columnDefinition = "timestamptz")
  private Instant archivedAt;

  protected Target() {}
}
