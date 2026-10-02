package com.teamdaisy.server.project.domain;

import jakarta.persistence.Column;
import jakarta.persistence.EmbeddedId;
import jakarta.persistence.Entity;
import jakarta.persistence.Table;
import java.time.Instant;

@Entity
@Table(name = "project_member")
public class ProjectMember {
  @EmbeddedId private ProjectMemberId id;

  @Column(name = "granted_by", nullable = false, length = 64)
  private String grantedBy;

  @Column(name = "granted_at", nullable = false, columnDefinition = "timestamptz")
  private Instant grantedAt;

  @Column(name = "revoked_at", nullable = true, columnDefinition = "timestamptz")
  private Instant revokedAt;

  protected ProjectMember() {}

  public static ProjectMember grant(
      String projectId, String accountId, String grantedBy, Instant now) {
    ProjectMember member = new ProjectMember();
    member.id = new ProjectMemberId(projectId, accountId);
    member.grantedBy = grantedBy;
    member.grantedAt = now;
    return member;
  }

  public ProjectMemberId id() {
    return id;
  }

  /** 접근 권한이 살아 있는지. 철회된 뒤에도 행은 남겨 이력을 지켜요. */
  public boolean isActive() {
    return revokedAt == null;
  }
}
