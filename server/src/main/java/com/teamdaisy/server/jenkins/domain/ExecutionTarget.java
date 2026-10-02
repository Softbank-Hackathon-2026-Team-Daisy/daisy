package com.teamdaisy.server.jenkins.domain;

import jakarta.persistence.Column;
import jakarta.persistence.EmbeddedId;
import jakarta.persistence.Entity;
import jakarta.persistence.Table;
import jakarta.persistence.UniqueConstraint;
import java.time.Instant;

@Entity
@Table(
    name = "execution_target",
    uniqueConstraints = {
      @UniqueConstraint(columnNames = {"execution_id", "deployment_target_id", "deployment_id"})
    })
public class ExecutionTarget {
  @EmbeddedId private ExecutionTargetId id;

  @Column(name = "deployment_id", nullable = false, length = 64)
  private String deploymentId;

  @Column(name = "input_hash", nullable = true, length = 128)
  private String inputHash;

  @Column(name = "plan_id", nullable = true, length = 64)
  private String planId;

  @Column(name = "plan_digest", nullable = true, length = 128)
  private String planDigest;

  @Column(name = "status", nullable = false, length = 32)
  private String status;

  @Column(name = "last_source_sequence", nullable = true)
  private Long lastSourceSequence;

  @Column(name = "started_at", nullable = true, columnDefinition = "timestamptz")
  private Instant startedAt;

  @Column(name = "finished_at", nullable = true, columnDefinition = "timestamptz")
  private Instant finishedAt;

  protected ExecutionTarget() {}
}
