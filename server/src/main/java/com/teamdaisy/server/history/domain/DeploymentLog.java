package com.teamdaisy.server.history.domain;

import com.fasterxml.jackson.databind.JsonNode;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import jakarta.persistence.UniqueConstraint;
import java.time.Instant;
import org.hibernate.annotations.JdbcTypeCode;
import org.hibernate.type.SqlTypes;

@Entity
@Table(
    name = "deployment_log",
    uniqueConstraints = {
      @UniqueConstraint(columnNames = {"id", "deployment_id"}),
      @UniqueConstraint(columnNames = {"deployment_id", "seq"}),
      @UniqueConstraint(columnNames = {"source", "source_event_id"})
    })
public class DeploymentLog {
  @Id
  @GeneratedValue(strategy = GenerationType.IDENTITY)
  @Column(name = "id", nullable = false)
  private Long id;

  @Column(name = "deployment_id", nullable = false, length = 64)
  private String deploymentId;

  @Column(name = "execution_id", nullable = true, length = 64)
  private String executionId;

  @Column(name = "deployment_target_id", nullable = true, length = 64)
  private String deploymentTargetId;

  @Column(name = "seq", nullable = false)
  private long seq;

  @Column(name = "source", nullable = false, length = 512)
  private String source;

  @Column(name = "source_event_id", nullable = false, length = 255)
  private String sourceEventId;

  @Column(name = "source_sequence", nullable = true)
  private Long sourceSequence;

  @Column(name = "payload_hash", nullable = false, length = 128)
  private String payloadHash;

  @Column(name = "event_type", nullable = false, length = 64)
  private String eventType;

  @Column(name = "stage_occurrence_id", nullable = true, length = 255)
  private String stageOccurrenceId;

  @Column(name = "step", nullable = true, length = 32)
  private String step;

  @Column(name = "level", nullable = false, length = 16)
  private String level;

  @Column(name = "message", nullable = true, columnDefinition = "text")
  private String message;

  @JdbcTypeCode(SqlTypes.JSON)
  @Column(name = "payload", nullable = false, columnDefinition = "jsonb")
  private JsonNode payload;

  @Column(name = "processing_result", nullable = false, length = 32)
  private String processingResult;

  @Column(name = "source_stream", nullable = true, length = 512)
  private String sourceStream;

  @Column(name = "source_offset", nullable = true)
  private Long sourceOffset;

  @Column(name = "source_end_offset", nullable = true)
  private Long sourceEndOffset;

  @Column(name = "occurred_at", nullable = false, columnDefinition = "timestamptz")
  private Instant occurredAt;

  @Column(name = "received_at", nullable = false, columnDefinition = "timestamptz")
  private Instant receivedAt;

  protected DeploymentLog() {}
}
