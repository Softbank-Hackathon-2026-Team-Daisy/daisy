package com.teamdaisy.server.project.web;

import com.fasterxml.jackson.databind.JsonNode;
import com.teamdaisy.server.common.error.DaisyException;
import com.teamdaisy.server.common.error.ErrorCode;
import com.teamdaisy.server.idempotency.application.IdempotencyService;
import org.springframework.http.ResponseEntity;

/**
 * 배포 명령(생성·승인·취소·재시도·롤백)의 접수 결과예요. 배포 성공이 아니라 접수됐다는 뜻이에요.
 *
 * <p>필드 이름은 소비자 {@code Deployment} 모델({@code ios/SPEC.md} 326행)과 같아요 — 웹은 응답의 {@code id} 로 다음 화면에
 * 가요. 재시도·롤백의 {@code id} 는 새로 만든 배포예요. 나머지 필드는 A-04 를 만들 때 같은 모델로 채워요.
 */
public record DeploymentAccepted(String id, String projectId, String state) {
  static final String IDEMPOTENCY_KEY = "Idempotency-Key";

  /** 실행 서비스의 응답을 상태 코드 그대로 소비자 이름으로 바꿔요. */
  static ResponseEntity<DeploymentAccepted> from(
      IdempotencyService.Response response, String projectId) {
    JsonNode body = response.body();
    return ResponseEntity.status(response.status())
        .body(
            new DeploymentAccepted(
                body.path("deployment_id").asText(null),
                projectId,
                body.path("status").asText(null)));
  }

  /** 배포 명령은 전부 멱등 키가 필수예요 (server/AGENTS.md §6). */
  static void requireKey(String key) {
    if (key == null || key.isBlank() || key.length() > 255) {
      throw new DaisyException(ErrorCode.VALIDATION_FAILED);
    }
  }
}
