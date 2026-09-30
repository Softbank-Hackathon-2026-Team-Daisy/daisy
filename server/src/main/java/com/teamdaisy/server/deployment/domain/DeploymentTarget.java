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
}
