package com.teamdaisy.server.common.error;

public enum ErrorCode {
  VALIDATION_FAILED(400, "요청 입력을 확인해 주세요."),
  UNAUTHENTICATED(401, "인증이 필요합니다."),
  FORBIDDEN(403, "요청을 수행할 권한이 없습니다."),
  NOT_FOUND(404, "요청한 정보를 찾을 수 없습니다."),
  TARGET_LOCKED(409, "해당 대상에서 다른 배포가 진행 중입니다."),
  STATE_CONFLICT(409, "현재 상태에서는 요청을 수행할 수 없습니다."),
  USERNAME_TAKEN(409, "이미 사용 중인 아이디예요."),
  MANIFEST_INVALID(422, "배포 명세를 확인해 주세요."),
  RATE_LIMITED(429, "요청이 많습니다. 잠시 후 다시 시도해 주세요."),
  INTERNAL(500, "요청 처리 중 오류가 발생했습니다.");

  private final int status;
  private final String message;

  ErrorCode(int status, String message) {
    this.status = status;
    this.message = message;
  }

  public int status() {
    return status;
  }

  public String message() {
    return message;
  }

  public boolean retryable() {
    return this == RATE_LIMITED;
  }
}
