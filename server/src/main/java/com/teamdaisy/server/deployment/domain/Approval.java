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

  public static Approval pending(String id, PlanRevision plan, Instant now, Instant expiry) {
    plan.assertUsable(plan.id(), plan.digest(), plan.inputHash(), now);
    DomainChecks.time(expiry);
    if (!expiry.isAfter(now) || expiry.isAfter(plan.expiresAt())) DomainChecks.invalid();
    var value = new Approval();
    value.id = DomainChecks.id(id);
    value.planId = plan.id();
    value.deploymentTargetId = plan.deploymentTargetId();
    value.state = "pending";
    value.createdAt = now;
    value.expiresAt = expiry;
    return value;
  }

  public void decide(
      PlanRevision plan,
      DeploymentTarget target,
      String actor,
      boolean approved,
      String confirmation,
      Instant now) {
    DomainChecks.id(actor);
    DomainChecks.time(now);
    DomainChecks.require(
        "pending".equals(state)
            && now.isBefore(expiresAt)
            && !now.isBefore(createdAt)
            && planId.equals(plan.id())
            && deploymentTargetId.equals(target.id())
            && planId.equals(target.currentPlanId())
            && target.status() == DeploymentTargetStatus.AWAITING_APPROVAL);
    plan.assertUsable(planId, plan.digest(), target.inputHash(), now);
    if (confirmation != null && confirmation.length() > 128) DomainChecks.invalid();
    if (approved && plan.hasDelete()) {
      String expected = target.targetSnapshot().path("name").asText();
      if (!expected.equals(confirmation)) DomainChecks.invalid();
    }
    state = approved ? "approved" : "rejected";
    decision = state;
    decidedBy = actor;
    decidedAt = now;
    confirmationText = confirmation;
  }

  public void assertApproved(PlanRevision plan, DeploymentTarget target, Instant now) {
    DomainChecks.time(now);
    DomainChecks.require(
        "approved".equals(state)
            && "approved".equals(decision)
            && now.isBefore(expiresAt)
            && planId.equals(target.currentPlanId())
            && deploymentTargetId.equals(target.id()));
    plan.assertUsable(planId, plan.digest(), target.inputHash(), now);
  }

  public void invalidate(String reason, Instant now) {
    DomainChecks.text(reason, 255);
    DomainChecks.time(now);
    if ("superseded".equals(state) || "expired".equals(state)) return;
    state = "expired".equals(reason) ? "expired" : "superseded";
    invalidatedAt = now;
    invalidationReason = reason;
  }

  public String id() {
    return id;
  }

  public String planId() {
    return planId;
  }

  public String deploymentTargetId() {
    return deploymentTargetId;
  }

  public String state() {
    return state;
  }

  public String decision() {
    return decision;
  }

  public String decidedBy() {
    return decidedBy;
  }

  public Instant decidedAt() {
    return decidedAt;
  }

  public String confirmationText() {
    return confirmationText;
  }

  public Instant createdAt() {
    return createdAt;
  }

  public Instant expiresAt() {
    return expiresAt;
  }

  public Instant invalidatedAt() {
    return invalidatedAt;
  }

  public String invalidationReason() {
    return invalidationReason;
  }
}
