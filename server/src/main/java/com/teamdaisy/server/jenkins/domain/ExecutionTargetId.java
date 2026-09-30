package com.teamdaisy.server.jenkins.domain;

import jakarta.persistence.Column;
import jakarta.persistence.Embeddable;
import java.io.Serializable;
import java.util.Objects;

@Embeddable
public class ExecutionTargetId implements Serializable {
  private static final long serialVersionUID = 1L;

  @Column(name = "execution_id", nullable = false, length = 64)
  private String executionId;

  @Column(name = "deployment_target_id", nullable = false, length = 64)
  private String deploymentTargetId;

  protected ExecutionTargetId() {}

  public ExecutionTargetId(String executionId, String deploymentTargetId) {
    this.executionId = Objects.requireNonNull(executionId);
    this.deploymentTargetId = Objects.requireNonNull(deploymentTargetId);
  }

  @Override
  public boolean equals(Object other) {
    return this == other
        || other instanceof ExecutionTargetId that
            && Objects.equals(executionId, that.executionId)
            && Objects.equals(deploymentTargetId, that.deploymentTargetId);
  }

  @Override
  public int hashCode() {
    return Objects.hash(executionId, deploymentTargetId);
  }
}
