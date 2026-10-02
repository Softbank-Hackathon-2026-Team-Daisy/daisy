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
    name = "project_event",
    uniqueConstraints = {
      @UniqueConstraint(columnNames = {"project_id", "seq"}),
      @UniqueConstraint(columnNames = {"project_id", "source", "source_event_id"})
    })
public class ProjectEvent {
  @Id
  @GeneratedValue(strategy = GenerationType.IDENTITY)
  @Column(name = "id", nullable = false)
  private Long id;

  @Column(name = "project_id", nullable = false, length = 64)
  private String projectId;

  @Column(name = "deployment_id", nullable = true, length = 64)
  private String deploymentId;

  @Column(name = "source_version_id", nullable = true, length = 64)
  private String sourceVersionId;

  @Column(name = "deployment_log_id", nullable = true)
  private Long deploymentLogId;

  @Column(name = "seq", nullable = false)
  private long seq;

  @Column(name = "source", nullable = false, length = 512)
  private String source;

  @Column(name = "source_event_id", nullable = false, length = 255)
  private String sourceEventId;

  @Column(name = "payload_hash", nullable = false, length = 128)
  private String payloadHash;

  @Column(name = "event_type", nullable = false, length = 64)
  private String eventType;

  @JdbcTypeCode(SqlTypes.JSON)
  @Column(name = "payload", nullable = false, columnDefinition = "jsonb")
  private JsonNode payload;

  @Column(name = "occurred_at", nullable = false, columnDefinition = "timestamptz")
  private Instant occurredAt;

  @Column(name = "received_at", nullable = false, columnDefinition = "timestamptz")
  private Instant receivedAt;

  protected ProjectEvent() {}
}
