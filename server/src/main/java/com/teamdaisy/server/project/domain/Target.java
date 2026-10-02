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
    name = "target",
    uniqueConstraints = {@UniqueConstraint(columnNames = {"id", "project_id"})})
public class Target {
  @Id
  @Column(name = "id", nullable = false, length = 64)
  private String id;

  @Column(name = "project_id", nullable = false, length = 64)
  private String projectId;

  @Column(name = "name", nullable = false, length = 128)
  private String name;

  @Column(name = "environment_type", nullable = false, length = 32)
  private String environmentType;

  @Column(name = "state_identity", nullable = false, length = 512)
  private String stateIdentity;

  @JdbcTypeCode(SqlTypes.JSON)
  @Column(name = "config", nullable = false, columnDefinition = "jsonb")
  private JsonNode config;

  @Column(name = "config_revision", nullable = false)
  private long configRevision;

  @Column(name = "credential_ref", nullable = true, columnDefinition = "text")
  private String credentialRef;

  @Column(name = "credential_version", nullable = true, length = 255)
  private String credentialVersion;

  @Column(name = "connection_state", nullable = false, length = 32)
  private String connectionState;

  @Column(name = "connection_checked_at", nullable = true, columnDefinition = "timestamptz")
  private Instant connectionCheckedAt;

  @Column(name = "current_deployment_target_id", nullable = true, length = 64)
  private String currentDeploymentTargetId;

  @JdbcTypeCode(SqlTypes.JSON)
  @Column(name = "observed_state", nullable = true, columnDefinition = "jsonb")
  private JsonNode observedState;

  @Column(name = "observed_at", nullable = true, columnDefinition = "timestamptz")
  private Instant observedAt;

  @JdbcTypeCode(SqlTypes.JSON)
  @Column(name = "reuse_assessment", nullable = true, columnDefinition = "jsonb")
  private JsonNode reuseAssessment;

  @Column(name = "created_at", nullable = false, columnDefinition = "timestamptz")
  private Instant createdAt;

  @Column(name = "updated_at", nullable = false, columnDefinition = "timestamptz")
  private Instant updatedAt;

  @Column(name = "archived_at", nullable = true, columnDefinition = "timestamptz")
  private Instant archivedAt;

  protected Target() {}

  /**
   * 배포 대상을 만들어요. 지금은 데모 시딩만 쓰고, 사용자 등록 절차는 저장소 연결 계약이 정해진 뒤에 붙여요.
   *
   * <p>{@code connectionState} 를 호출자가 넘기게 둔 것은 일부러예요. 연결 확인을 한 적이 없는 대상을 {@code connected} 로 만들어 두면
   * 확인하지 않은 상태를 확인한 것처럼 보여 주게 돼요.
   */
  public static Target create(
      String id,
      String projectId,
      String name,
      String environmentType,
      String stateIdentity,
      JsonNode config,
      String connectionState,
      Instant now) {
    Target target = new Target();
    target.id = id;
    target.projectId = projectId;
    target.name = name;
    target.environmentType = environmentType;
    target.stateIdentity = stateIdentity;
    target.config = config;
    target.configRevision = 1L;
    target.connectionState = connectionState;
    target.createdAt = now;
    target.updatedAt = now;
    return target;
  }

  public String id() {
    return id;
  }

  public String projectId() {
    return projectId;
  }

  public String name() {
    return name;
  }

  public String environmentType() {
    return environmentType;
  }

  public String stateIdentity() {
    return stateIdentity;
  }

  public String connectionState() {
    return connectionState;
  }

  public Instant connectionCheckedAt() {
    return connectionCheckedAt;
  }

  /** 대상 설정이에요. 받는 쪽이 고쳐도 엔티티가 바뀌지 않게 복사본을 돌려줘요. */
  public JsonNode config() {
    return config == null ? null : config.deepCopy();
  }

  public long configRevision() {
    return configRevision;
  }

  /** 자격증명 참조예요. 실제 비밀값이 아니에요. */
  public String credentialRef() {
    return credentialRef;
  }

  public String credentialVersion() {
    return credentialVersion;
  }

  /** 인프라가 보고한 재사용 판정이에요. 보고가 없으면 null 이에요. 복사본을 돌려줘요. */
  public JsonNode reuseAssessment() {
    return reuseAssessment == null ? null : reuseAssessment.deepCopy();
  }

  /**
   * 현재 배포 대상 ID 예요. 대상은 이 모듈 소유라 실제 결과에 따라 갱신하는 서비스도 이 모듈이 열어야 하지만, 근거가 될 결과 계약(#35)이 정해지기 전이라 아직
   * 갱신하는 곳이 없어요 (server/SPEC.md ⑤). 그 전까지 이 값은 항상 null 이에요.
   *
   * <p>ID 로 가리키는 {@code deployment_target} 행을 읽으려면 deployment 모듈의 조회 서비스가 필요해요. 설계 2장의 소유 경계대로 그쪽
   * Repository 를 직접 쓰지 않아요.
   */
  public String currentDeploymentTargetId() {
    return currentDeploymentTargetId;
  }

  public boolean isArchived() {
    return archivedAt != null;
  }
}
