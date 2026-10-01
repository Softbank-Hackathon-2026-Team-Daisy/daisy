package com.teamdaisy.server.project.web;

import com.teamdaisy.server.project.domain.Target;
import java.time.Instant;

/**
 * 환경별 현재 상태 응답이에요 (A-02). 소비자 모델은 {@code ios/SPEC.md} §6-7 의 {@code TargetStatus} 예요.
 *
 * <p><b>없는 값을 만들어 넣지 않아요.</b> 인프라 산출물이 없어서 근거가 없는 필드는 null 로 두고, {@code health} 는 모른다는 뜻의 {@code
 * unknown} 을 보내요. 0 이나 빈 문자열로 채우면 소비자가 확인된 값으로 읽어요.
 */
public record TargetStatusResponse(
    String targetId,
    String type,
    String name,
    String connectionState,
    Instant checkedAt,
    Current current,
    String url,
    String health,
    String healthSummary,
    String imageDigest) {

  /** 아직 헬스 결과를 받는 경로가 없어요. 인프라의 {@code apply-result.json} 이 생기면 채워요. */
  private static final String HEALTH_UNKNOWN = "unknown";

  /**
   * 그 대상에 마지막으로 끝난 배포예요. 한 번도 없으면 통째로 null 이에요.
   *
   * <p>이 블록을 채우려면 {@code deployment} 모듈(승환 소유)의 조회 서비스가 필요해요. 설계 2장의 소유 경계대로 그쪽 Repository 를 직접 쓰지
   * 않아서, 계약이 생길 때까지 null 이에요. {@code []} 나 빈 객체로 바꾸지 않아요 — "배포가 없다" 와 "모른다" 를 구분해야 해요.
   */
  public record Current(String deploymentId, String commit, String image, Instant deployedAt) {}

  public static TargetStatusResponse of(Target target) {
    return new TargetStatusResponse(
        target.id(),
        target.environmentType(),
        target.name(),
        target.connectionState(),
        target.connectionCheckedAt(),
        null,
        null,
        HEALTH_UNKNOWN,
        null,
        null);
  }
}
