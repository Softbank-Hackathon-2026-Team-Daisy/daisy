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
}
