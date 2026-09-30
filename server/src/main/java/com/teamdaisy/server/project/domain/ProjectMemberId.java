package com.teamdaisy.server.project.domain;

import jakarta.persistence.Column;
import jakarta.persistence.Embeddable;
import java.io.Serializable;
import java.util.Objects;

@Embeddable
public class ProjectMemberId implements Serializable {
  private static final long serialVersionUID = 1L;

  @Column(name = "project_id", nullable = false, length = 64)
  private String projectId;

  @Column(name = "account_id", nullable = false, length = 64)
  private String accountId;

  protected ProjectMemberId() {}

  public ProjectMemberId(String projectId, String accountId) {
    this.projectId = Objects.requireNonNull(projectId);
    this.accountId = Objects.requireNonNull(accountId);
  }

  @Override
  public boolean equals(Object other) {
    return this == other
        || other instanceof ProjectMemberId that
            && Objects.equals(projectId, that.projectId)
            && Objects.equals(accountId, that.accountId);
  }

  @Override
  public int hashCode() {
    return Objects.hash(projectId, accountId);
  }
}
