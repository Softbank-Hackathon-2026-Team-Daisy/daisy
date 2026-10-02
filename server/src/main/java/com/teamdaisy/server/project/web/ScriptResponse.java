package com.teamdaisy.server.project.web;

import com.teamdaisy.server.project.application.ScriptReader.ScriptRow;
import io.swagger.v3.oas.annotations.media.Schema;
import java.time.Instant;

/**
 * 검증된 스크립트 한 줄이에요 (WR-10). 소비자 모델은 앱 {@code Script}, 웹 {@code Script} 예요.
 *
 * <p>파일 내용({@code files})은 넣지 않아요. 서버는 원본 참조만 갖고 있어요 (WR-07).
 *
 * @param version 앱·웹이 문자열로 받아서 {@code "s" + 버전} 이에요
 * @param origin 처음 검증한 대상이 재사용이면 reused, 재사용이 아니고 실제 생성 시도(1 이상)가 있으면 ai_generated, 그 밖(AI 없이 기준
 *     모듈을 쓴 경로, 출처 미확인)은 null 이에요 (#68 승환님 리뷰)
 * @param attempt 처음 검증한 대상의 시도 횟수예요. 0 이거나 그 대상이 없으면 null 이에요 (S2, A-04 와 같음)
 * @param status 원본을 쓸 수 없거나 보관 기한이 지났으면 discarded, 아니면 verified
 * @param lastUsedAt 이 스크립트를 쓴 대상이 끝난(없으면 시작한) 가장 늦은 시각. 쓴 적 없으면 null
 * @param createdAt 원천 검증 완료 시각이에요
 */
public record ScriptResponse(
    String scriptId,
    String targetId,
    String type,
    String version,
    @Schema(nullable = true) String origin,
    @Schema(nullable = true) Integer attempt,
    Validation validation,
    String status,
    long reuseCount,
    @Schema(nullable = true) Instant lastUsedAt,
    Instant createdAt) {

  /**
   * 검증 결과예요.
   *
   * @param validate 검증을 통과해야 저장되므로 늘 true 예요
   * @param plan 이 스크립트로 만든 plan 이 있으면 true
   * @param risks 가장 최근 plan 의 위험 설정 수. plan 이 없으면 null
   */
  public record Validation(
      boolean validate, boolean plan, @Schema(nullable = true) Integer risks) {}

  /**
   * 만든 방식이에요. 재사용이 아니라는 것만으로 AI 생성이라고 하지 않아요. 인프라에는 AI 없이 기준 모듈을 쓰는 경로(USE_AI=false)가 있어서, 그 경우 시도
   * 0·재사용 false 가 함께 나와요.
   */
  static String origin(Boolean reused, Integer attempt) {
    if (Boolean.TRUE.equals(reused)) {
      return "reused";
    }
    if (Boolean.FALSE.equals(reused) && attempt != null && attempt > 0) {
      return "ai_generated";
    }
    return null;
  }

  static ScriptResponse of(ScriptRow row, Instant now) {
    String origin = origin(row.sourceReused(), row.sourceAttempt());
    boolean discarded =
        row.unavailableAt() != null
            || (row.artifactExpiresAt() != null && !row.artifactExpiresAt().isAfter(now));
    return new ScriptResponse(
        row.id(),
        row.targetId(),
        row.environmentType(),
        "s" + row.version(),
        origin,
        row.sourceAttempt() == null || row.sourceAttempt() == 0 ? null : row.sourceAttempt(),
        new Validation(true, row.planCount() > 0, row.latestRisks()),
        discarded ? "discarded" : "verified",
        row.reuseCount(),
        row.lastUsedAt(),
        row.validatedAt());
  }
}
