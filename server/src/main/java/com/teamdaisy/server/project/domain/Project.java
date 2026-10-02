package com.teamdaisy.server.project.domain;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import java.time.Instant;

@Entity
@Table(name = "project")
public class Project {
  @Id
  @Column(name = "id", nullable = false, length = 64)
  private String id;

  @Column(name = "name", nullable = false, length = 128)
  private String name;

  @Column(name = "repository_id", nullable = false, length = 255)
  private String repositoryId;

  @Column(name = "repository_url", nullable = false, columnDefinition = "text")
  private String repositoryUrl;

  @Column(name = "default_branch", nullable = false, length = 255)
  private String defaultBranch;

  @Column(name = "manifest_path", nullable = false, length = 512)
  private String manifestPath;

  @Column(name = "repository_credential_ref", nullable = true, columnDefinition = "text")
  private String repositoryCredentialRef;

  @Column(name = "created_by", nullable = false, length = 64)
  private String createdBy;

  @Column(name = "last_event_seq", nullable = false)
  private long lastEventSeq;

  @Column(name = "created_at", nullable = false, columnDefinition = "timestamptz")
  private Instant createdAt;

  @Column(name = "updated_at", nullable = false, columnDefinition = "timestamptz")
  private Instant updatedAt;

  @Column(name = "archived_at", nullable = true, columnDefinition = "timestamptz")
  private Instant archivedAt;

  protected Project() {}

  public static Project connect(
      String id,
      String name,
      String repositoryId,
      String repositoryUrl,
      String defaultBranch,
      String manifestPath,
      String createdBy,
      Instant now) {
    Project project = new Project();
    project.id = id;
    project.name = name;
    project.repositoryId = repositoryId;
    project.repositoryUrl = repositoryUrl;
    project.defaultBranch = defaultBranch;
    project.manifestPath = manifestPath;
    project.createdBy = createdBy;
    project.createdAt = now;
    project.updatedAt = now;
    return project;
  }

  public String id() {
    return id;
  }

  public String name() {
    return name;
  }

  public String repositoryId() {
    return repositoryId;
  }

  public String repositoryUrl() {
    return repositoryUrl;
  }

  public String defaultBranch() {
    return defaultBranch;
  }

  public String manifestPath() {
    return manifestPath;
  }

  /** 저장소 자격증명 참조예요. 실제 비밀값이 아니에요. */
  public String repositoryCredentialRef() {
    return repositoryCredentialRef;
  }

  public Instant createdAt() {
    return createdAt;
  }

  public Instant archivedAt() {
    return archivedAt;
  }
}
