package com.teamdaisy.server.project.domain;

import com.fasterxml.jackson.databind.JsonNode;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import jakarta.persistence.UniqueConstraint;
import java.time.Instant;
import org.hibernate.annotations.JdbcTypeCode;
import org.hibernate.type.SqlTypes;

@Entity
@Table(
    name = "source_version",
    uniqueConstraints = {
      @UniqueConstraint(columnNames = {"id", "project_id"}),
      @UniqueConstraint(columnNames = {"source", "external_build_id"})
    })
public class SourceVersion {
  @Id
  @Column(name = "id", nullable = false, length = 64)
  private String id;

  @Column(name = "project_id", nullable = false, length = 64)
  private String projectId;

  @Column(name = "source", nullable = false, length = 255)
  private String source;

  @Column(name = "external_build_id", nullable = false, length = 255)
  private String externalBuildId;

  @Column(name = "commit_sha", nullable = false, length = 64)
  private String commitSha;

  @Column(name = "branch", nullable = true, length = 255)
  private String branch;

  @Column(name = "status", nullable = false, length = 32)
  private String status;

  @JdbcTypeCode(SqlTypes.JSON)
  @Column(name = "image_refs", nullable = true, columnDefinition = "jsonb")
  private JsonNode imageRefs;

  @JdbcTypeCode(SqlTypes.JSON)
  @Column(name = "manifest_snapshot", nullable = true, columnDefinition = "jsonb")
  private JsonNode manifestSnapshot;

  @Column(name = "manifest_ref", nullable = true, columnDefinition = "text")
  private String manifestRef;

  @Column(name = "manifest_digest", nullable = true, length = 128)
  private String manifestDigest;

  @Column(name = "manifest_schema_version", nullable = true, length = 64)
  private String manifestSchemaVersion;

  @Column(name = "run_url", nullable = true, columnDefinition = "text")
  private String runUrl;

  @Column(name = "started_at", nullable = true, columnDefinition = "timestamptz")
  private Instant startedAt;

  @Column(name = "finished_at", nullable = true, columnDefinition = "timestamptz")
  private Instant finishedAt;

  @Column(name = "error_summary", nullable = true, columnDefinition = "text")
  private String errorSummary;

  @Column(name = "received_at", nullable = false, columnDefinition = "timestamptz")
  private Instant receivedAt;

  protected SourceVersion() {}

  public String id() {
    return id;
  }

  public String projectId() {
    return projectId;
  }

  public String commitSha() {
    return commitSha;
  }

  public String branch() {
    return branch;
  }

  /** DB 값이에요. API 로 내보낼 때는 소비자 enum 으로 변환해요 (`BuildResponse` 참고). */
  public String status() {
    return status;
  }

  /**
   * 서비스별 이미지 객체예요. 채우는 쪽은 승환 빌드 수신 서비스고 쓰는 쪽이 이 모듈이에요.
   *
   * <p>정확한 모양은 설계 5.5 가 "성공 시 확정한 service별 이미지 객체" 로만 두어서 아직 확정이 아니에요. 가정한 모양과 다를 때 조회가 깨지지 않도록
   * 평탄화에서 방어해요.
   */
  public JsonNode imageRefs() {
    return imageRefs;
  }

  public String runUrl() {
    return runUrl;
  }

  public Instant startedAt() {
    return startedAt;
  }

  public Instant finishedAt() {
    return finishedAt;
  }

  public String errorSummary() {
    return errorSummary;
  }

  public Instant receivedAt() {
    return receivedAt;
  }
}
