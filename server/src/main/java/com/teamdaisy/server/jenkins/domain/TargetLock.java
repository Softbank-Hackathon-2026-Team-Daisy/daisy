package com.teamdaisy.server.jenkins.domain;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import jakarta.persistence.UniqueConstraint;
import java.time.Instant;

@Entity
@Table(
    name = "target_lock",
    uniqueConstraints = {@UniqueConstraint(columnNames = {"execution_id", "deployment_target_id"})})
public class TargetLock {
  @Id
  @Column(name = "state_identity", nullable = false, length = 512)
  private String stateIdentity;

  @Column(name = "execution_id", nullable = false, length = 64)
  private String executionId;

  @Column(name = "deployment_target_id", nullable = false, length = 64)
  private String deploymentTargetId;

  @Column(name = "acquired_at", nullable = false, columnDefinition = "timestamptz")
  private Instant acquiredAt;

  protected TargetLock() {}
}
