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
import org.hibernate.annotations.JdbcTypeCode;
import org.hibernate.type.SqlTypes;

@Entity
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
}
