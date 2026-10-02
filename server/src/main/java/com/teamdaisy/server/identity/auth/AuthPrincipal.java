package com.teamdaisy.server.identity.auth;

/**
 * 인증된 요청의 주체예요. Bearer 토큰을 검증한 뒤에만 만들어져요.
 *
 * <p>사용자가 보낸 값을 그대로 믿지 않아요. role 은 토큰이 아니라 DB 의 계정에서 읽어요.
 */
public record AuthPrincipal(String accountId, String username, String role) {
  public static final String VIEWER = "viewer";

  /** 읽기 전용 계정인지. 변경·승인 요청에서 막아요. */
  public boolean readOnly() {
    return VIEWER.equals(role);
  }
}
