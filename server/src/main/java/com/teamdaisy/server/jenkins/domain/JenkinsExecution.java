package com.teamdaisy.server.jenkins.domain;

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
    name = "jenkins_execution",
    uniqueConstraints = {
      @UniqueConstraint(columnNames = {"request_id"}),
      @UniqueConstraint(columnNames = {"id", "deployment_id"})
    })
public class JenkinsExecution {
  @Id
  @Column(name = "id", nullable = false, length = 64)
  private String id;

  @Column(name = "deployment_id", nullable = false, length = 64)
  private String deploymentId;

  @Column(name = "request_id", nullable = false, length = 128)
  private String requestId;

  @Column(name = "operation", nullable = false, length = 32)
  private String operation;

  @Column(name = "parent_execution_id", nullable = true, length = 64)
  private String parentExecutionId;

  @Column(name = "instance_id", nullable = false, length = 128)
  private String instanceId;

  @Column(name = "job_full_name", nullable = false, length = 512)
  private String jobFullName;

  @JdbcTypeCode(SqlTypes.JSON)
  @Column(name = "request_payload", nullable = false, columnDefinition = "jsonb")
  private JsonNode requestPayload;

  @Column(name = "request_hash", nullable = false, length = 128)
  private String requestHash;

  @Column(name = "dispatch_status", nullable = false, length = 32)
  private String dispatchStatus;

  @Column(name = "run_status", nullable = false, length = 32)
  private String runStatus;

  @Column(name = "dispatch_attempts", nullable = false)
  private int dispatchAttempts;

  @Column(name = "dispatch_started_at", nullable = true, columnDefinition = "timestamptz")
  private Instant dispatchStartedAt;

  @Column(name = "queue_id", nullable = true)
  private Long queueId;

  @Column(name = "build_number", nullable = true)
  private Long buildNumber;

  @Column(name = "run_url", nullable = true, columnDefinition = "text")
  private String runUrl;

  @Column(name = "log_owner_execution_id", nullable = true, length = 64)
  private String logOwnerExecutionId;

  @Column(name = "log_cursor", nullable = false)
  private long logCursor;

  @Column(name = "log_complete", nullable = false)
  private boolean logComplete;

  @Column(name = "next_check_at", nullable = true, columnDefinition = "timestamptz")
  private Instant nextCheckAt;

  @Column(name = "last_checked_at", nullable = true, columnDefinition = "timestamptz")
  private Instant lastCheckedAt;

  @Column(name = "last_error", nullable = true, columnDefinition = "text")
  private String lastError;

  @Column(name = "created_at", nullable = false, columnDefinition = "timestamptz")
  private Instant createdAt;

  @Column(name = "started_at", nullable = true, columnDefinition = "timestamptz")
  private Instant startedAt;

  @Column(name = "finished_at", nullable = true, columnDefinition = "timestamptz")
  private Instant finishedAt;

  protected JenkinsExecution() {}
}
