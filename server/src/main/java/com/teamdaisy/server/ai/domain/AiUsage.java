package com.teamdaisy.server.ai.domain;

import com.fasterxml.jackson.databind.JsonNode;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import jakarta.persistence.UniqueConstraint;
import java.math.BigDecimal;
import java.time.Instant;
import org.hibernate.annotations.JdbcTypeCode;
import org.hibernate.type.SqlTypes;

@Entity
@Table(
    name = "ai_usage",
    uniqueConstraints = {@UniqueConstraint(columnNames = {"source", "external_call_id"})})
public class AiUsage {
  @Id
  @Column(name = "id", nullable = false, length = 64)
  private String id;

  @Column(name = "execution_id", nullable = false, length = 64)
  private String executionId;

  @Column(name = "deployment_target_id", nullable = false, length = 64)
  private String deploymentTargetId;

  @Column(name = "source", nullable = false, length = 512)
  private String source;

  @Column(name = "external_call_id", nullable = false, length = 255)
  private String externalCallId;

  @Column(name = "payload_hash", nullable = false, length = 128)
  private String payloadHash;

  @Column(name = "provider", nullable = false, length = 64)
  private String provider;

  @Column(name = "model", nullable = false, length = 128)
  private String model;

  @Column(name = "step", nullable = false, length = 32)
  private String step;

  @Column(name = "attempt", nullable = false)
  private short attempt;

  @Column(name = "status", nullable = false, length = 32)
  private String status;

  @Column(name = "input_tokens", nullable = true)
  private Long inputTokens;

  @Column(name = "output_tokens", nullable = true)
  private Long outputTokens;

  @JdbcTypeCode(SqlTypes.JSON)
  @Column(name = "usage_details", nullable = true, columnDefinition = "jsonb")
  private JsonNode usageDetails;

  @Column(name = "cost_usd", nullable = true, precision = 20, scale = 10)
  private BigDecimal costUsd;

  @Column(name = "cost_basis", nullable = true, length = 32)
  private String costBasis;

  @Column(name = "occurred_at", nullable = false, columnDefinition = "timestamptz")
  private Instant occurredAt;

  @Column(name = "received_at", nullable = false, columnDefinition = "timestamptz")
  private Instant receivedAt;

  protected AiUsage() {}
}
