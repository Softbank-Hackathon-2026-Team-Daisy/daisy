package com.teamdaisy.server.project.web;

import com.fasterxml.jackson.databind.JsonNode;
import com.teamdaisy.server.project.application.DeploymentDetailReader.DeploymentDetail;
import com.teamdaisy.server.project.application.DeploymentDetailReader.DeploymentRow;
import com.teamdaisy.server.project.application.DeploymentDetailReader.PendingApproval;
import com.teamdaisy.server.project.application.DeploymentDetailReader.TargetRow;
import com.teamdaisy.server.project.web.BuildResponse.ServiceImage;
import java.time.Instant;
import java.util.List;
import java.util.regex.Pattern;

/**
 * 배포 상세예요 (A-04). 소비자 모델은 {@code ios/SPEC.md} 326행 {@code Deployment} 예요.
 *
 * <p><b>없는 값을 만들어 넣지 않아요.</b> 접속 URL·실제 적용 이미지는 성공 콜백이 저장한 {@code deployment_target.result} 에서 읽고,
 * 없거나 서비스가 여럿이면 null 이에요. 헬스는 {@code result} 에 근거가 없어서 null 이에요. 단계는 승환의 Jenkins 수신이 {@code
 * deployment_log} 에 남긴 가장 최근 {@code step.*} 이벤트로 정하고, 없으면 null 이에요 (A-07 과 함께 붙임). 시도 횟수 0 은 null 로
 * 보내요 (S2).
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
  private static final Pattern DIGEST = Pattern.compile("sha256:[0-9a-f]{64}");

  /**
   * 대상 하나예요.
   *
   * @param step 가장 최근 단계 이벤트의 단계. 이벤트가 없으면 null 이에요
   * @param stepState running·done·failed. 이벤트가 없으면 null 이고, waiting 은 근거가 없어 만들지 않아요
   * @param approvalState 현재 plan 승인 행의 상태 그대로 (pending·approved·rejected·superseded·expired). 없으면
   *     null 이에요. 승인 직후 apply 가 시작되기 전에는 대상 state 가 awaiting_approval 이어도 approved 예요
   * @param applyDispatch 현재 명령이 apply 일 때만 queued·unknown·rejected. 아니면 null 이에요
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
      Instant finishedAt,
      String approvalState,
      String applyDispatch) {}

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
        row.step(),
        row.stepState(),
        row.attempt() == 0 ? null : row.attempt(),
        row.aiReused(),
        url(row.result()),
        imageDigest(row.result()),
        null,
        row.errorSummary(),
        row.cancelRequestedAt(),
        row.startedAt(),
        row.finishedAt(),
        row.approvalState(),
        row.applyDispatch());
  }

  /** 성공 콜백의 {@code public_urls} 에서 서비스가 정확히 하나일 때만 그 주소예요. 여럿이면 대표를 고르지 않아요 (S5). */
  static String url(JsonNode result) {
    JsonNode only = onlyService(result, "public_urls");
    return only != null && only.isTextual() ? only.asText() : null;
  }

  /** 성공 콜백의 {@code image_refs} 에서 서비스가 정확히 하나이고 digest 형식이 맞을 때만 그 값이에요. */
  static String imageDigest(JsonNode result) {
    JsonNode only = onlyService(result, "image_refs");
    String digest = only == null ? null : text(only, "digest");
    return digest != null && DIGEST.matcher(digest).matches() ? digest : null;
  }

  private static JsonNode onlyService(JsonNode result, String key) {
    JsonNode services = result == null || !result.isObject() ? null : result.get(key);
    if (services == null || !services.isObject() || services.size() != 1) {
      return null;
    }
    return services.elements().next();
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
