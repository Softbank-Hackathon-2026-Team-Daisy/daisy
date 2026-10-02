package com.teamdaisy.server.project.web;

import com.teamdaisy.server.deployment.application.DeploymentQueryService.CurrentDeployment;
import com.teamdaisy.server.project.application.DeploymentHistoryReader.CurrentView;
import com.teamdaisy.server.project.domain.Target;
import com.teamdaisy.server.project.web.BuildResponse.ServiceImage;
import java.time.Instant;
import java.util.List;

/**
 * 환경별 현재 상태 응답이에요 (A-02). 소비자 모델은 {@code ios/SPEC.md} §6-7 의 {@code TargetStatus} 예요.
 *
 * <p><b>없는 값을 만들어 넣지 않아요.</b> 인프라 산출물이 없어서 근거가 없는 필드는 null 로 두고, {@code health} 는 모른다는 뜻의 {@code
 * unknown} 을 보내요. 0 이나 빈 문자열로 채우면 소비자가 확인된 값으로 읽어요.
 *
 * @param current 확인된 현재 배포. 없으면 null 이에요
 * @param currentStatus {@code none}·{@code confirmed}·{@code unverified}. {@code current} 가 null 인
 *     이유를 구분해요
 */
public record TargetStatusResponse(
    String targetId,
    String type,
    String name,
    String connectionState,
    Instant checkedAt,
    Current current,
    String currentStatus,
    String url,
    String health,
    String healthSummary,
    String imageDigest) {

  /** 아직 헬스 결과를 받는 경로가 없어요. 인프라의 {@code apply-result.json} 이 생기면 채워요. */
  private static final String HEALTH_UNKNOWN = "unknown";

  /**
   * 대상의 현재 포인터가 가리키는 성공 배포예요 (승환 조회 계약).
   *
   * <p><b>null 은 "배포가 없다" 가 아니라 "확인된 현재 참조가 없다" 예요.</b> 지금은 포인터를 갱신하는 곳이 없어서 실제로 배포됐어도 null 이에요.
   * 그래서 {@code current_status} 를 함께 보내요. {@code []} 나 빈 객체로 바꾸지 않아요.
   *
   * <p>이미지는 서비스가 정확히 하나일 때만 {@code image}·{@code image_digest} 에 넣어요. 여럿이면 둘 다 null 로 두고 {@code
   * images} 를 줘요. 대표 하나를 고르지 않아요 (S5, A-06 과 같은 규칙).
   *
   * @param deployedAt 대상 성공 완료 시각이에요. 트래픽 전환 시각을 잰 값이 아니에요
   */
  public record Current(
      String deploymentId,
      String commit,
      String image,
      String imageDigest,
      List<ServiceImage> images,
      Instant deployedAt) {

    static Current of(CurrentDeployment deployment) {
      List<ServiceImage> images =
          deployment.images() == null
              ? null
              : deployment.images().stream()
                  .map(i -> new ServiceImage(i.service(), i.imageRef(), i.imageDigest()))
                  .toList();
      boolean single = images != null && images.size() == 1;
      return new Current(
          deployment.deploymentId(),
          deployment.commitSha(),
          single ? images.get(0).imageRef() : null,
          single ? images.get(0).imageDigest() : null,
          single ? null : images,
          deployment.deployedAt());
    }
  }

  public static TargetStatusResponse of(Target target) {
    return of(target, CurrentView.none());
  }

  public static TargetStatusResponse of(Target target, CurrentView view) {
    return new TargetStatusResponse(
        target.id(),
        target.environmentType(),
        target.name(),
        TargetResponse.connectionState(target.connectionState()),
        target.connectionCheckedAt(),
        view.deployment() == null ? null : Current.of(view.deployment()),
        view.status(),
        null,
        HEALTH_UNKNOWN,
        null,
        null);
  }
}
