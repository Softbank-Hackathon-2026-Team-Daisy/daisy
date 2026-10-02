package com.teamdaisy.server.deployment.domain;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import jakarta.persistence.UniqueConstraint;
import java.time.Instant;

@Entity
@Table(
    name = "approval",
    uniqueConstraints = {@UniqueConstraint(columnNames = {"plan_id"})})
public class Approval {
  @Id
  @Column(name = "id", nullable = false, length = 64)
  private String id;

  @Column(name = "plan_id", nullable = false, length = 64)
  private String planId;

  @Column(name = "deployment_target_id", nullable = false, length = 64)
  private String deploymentTargetId;

  @Column(name = "state", nullable = false, length = 32)
  private String state;

  @Column(name = "decision", nullable = true, length = 32)
  private String decision;

  @Column(name = "decided_by", nullable = true, length = 64)
  private String decidedBy;

  @Column(name = "decided_at", nullable = true, columnDefinition = "timestamptz")
  private Instant decidedAt;

  @Column(name = "confirmation_text", nullable = true, length = 128)
  private String confirmationText;

  @Column(name = "created_at", nullable = false, columnDefinition = "timestamptz")
  private Instant createdAt;

  @Column(name = "expires_at", nullable = false, columnDefinition = "timestamptz")
  private Instant expiresAt;

  @Column(name = "invalidated_at", nullable = true, columnDefinition = "timestamptz")
  private Instant invalidatedAt;

  @Column(name = "invalidation_reason", nullable = true, length = 255)
  private String invalidationReason;

  protected Approval() {}
}
