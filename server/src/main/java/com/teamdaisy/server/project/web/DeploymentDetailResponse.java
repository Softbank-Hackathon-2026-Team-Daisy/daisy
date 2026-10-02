package com.teamdaisy.server.project.web;

import com.fasterxml.jackson.databind.JsonNode;
import com.teamdaisy.server.project.application.DeploymentDetailReader.DeploymentDetail;
import com.teamdaisy.server.project.application.DeploymentDetailReader.DeploymentRow;
import com.teamdaisy.server.project.application.DeploymentDetailReader.PendingApproval;
import com.teamdaisy.server.project.application.DeploymentDetailReader.TargetRow;
import com.teamdaisy.server.project.web.BuildResponse.ServiceImage;
import java.time.Instant;
import java.util.List;

/**
 * 배포 상세예요 (A-04). 소비자 모델은 {@code ios/SPEC.md} 326행 {@code Deployment} 예요.
 *
 * <p><b>없는 값을 만들어 넣지 않아요.</b> 접속 URL·실제 적용 이미지·헬스는 근거 데이터가 아직 없어서 null 이에요 (apply 결과 수신 #35 대기).
 * 단계는 승환의 Jenkins 수신이 {@code deployment_log} 에 {@code step.*} 이벤트로 남기지만 여기서는 아직 읽지 않아서 null 이에요 —
 * 같은 테이블을 읽는 A-07 로그 조회와 함께 붙여요. 시도 횟수 0 은 null 로 보내요 (S2).
 *
 * @param kind 롤백이면 {@code "rollback"}, 아니면 null. 내부 값 {@code normal}·{@code retry} 는 내보내지 않아요
 * @param pendingApprovals 승인 요청 {@code items} 와 같은 모양이에요. 없으면 빈 목록이에요
 * @param lastSeq SSE 재연결 기준점이에요
 */
public record DeploymentDetailResponse(
    String id,
    String projectId,
    String sourceVersionId,
    String commit,
    String image,
    String imageDigest,
    List<ServiceImage> images,
    String state,
    String kind,
    String rolledBackFrom,
    String retryOf,
    List<Target> targets,
    List<Approval> pendingApprovals,
    String createdBy,
    Instant createdAt,
    Instant finishedAt,
    long lastSeq) {

  private static final String ROLLBACK = "rollback";

  /**
   * 대상 하나예요.
   *
   * @param step 아직 {@code deployment_log} 의 단계 이벤트를 읽지 않아서 null 이에요
   * @param attempt 첫 생성을 포함한 시도 횟수(1~3). 아직 생성 전이면 null 이에요
   */
  public record Target(
      String targetId,
      String type,
      String name,
      String state,
      String step,
      String stepState,
      Integer attempt,
      boolean reusedScript,
      String url,
      String imageDigest,
      String healthSummary,
      String errorSummary,
      Instant cancelRequestedAt,
      Instant startedAt,
      Instant finishedAt) {}

  public record Approval(String targetId, String approvalId) {}

  public static DeploymentDetailResponse of(DeploymentDetail detail) {
    DeploymentRow d = detail.deployment();
    BuildResponse.Images images = BuildResponse.flatten(d.imageRefs());
    return new DeploymentDetailResponse(
        d.id(),
        d.projectId(),
        d.sourceVersionId(),
        d.commitSha(),
        images.image(),
        images.imageDigest(),
        images.images(),
        d.status(),
        ROLLBACK.equals(d.kind()) ? ROLLBACK : null,
        d.rollbackOf(),
        d.retryOf(),
        detail.targets().stream().map(DeploymentDetailResponse::target).toList(),
        detail.pendingApprovals().stream().map(DeploymentDetailResponse::approval).toList(),
        d.createdBy(),
        d.createdAt(),
        d.finishedAt(),
        d.lastSeq());
  }

  static Target target(TargetRow row) {
    return new Target(
        row.targetId(),
        text(row.snapshot(), "environment_type"),
        text(row.snapshot(), "name"),
        row.status(),
        null,
        null,
        row.attempt() == 0 ? null : row.attempt(),
        row.aiReused(),
        null,
        null,
        null,
        row.errorSummary(),
        row.cancelRequestedAt(),
        row.startedAt(),
        row.finishedAt());
  }

  private static Approval approval(PendingApproval pending) {
    return new Approval(pending.targetId(), pending.approvalId());
  }

  private static String text(JsonNode node, String key) {
    if (node == null) {
      return null;
    }
    JsonNode value = node.get(key);
    return value != null && value.isTextual() ? value.asText() : null;
  }
}
