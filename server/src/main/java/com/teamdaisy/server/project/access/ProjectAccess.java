package com.teamdaisy.server.project.access;

import com.teamdaisy.server.identity.auth.AuthPrincipal;

/**
 * 한 요청에서 확인된 프로젝트 접근 결과예요.
 *
 * <p>조회가 가능한지와 변경·승인이 가능한지를 나눠서 담아요. 설계상 접근 여부는 활성 membership 으로, 변경·승인 여부는 계정 역할로 판단해요
 * (database-design.md 5.3).
 */
public record ProjectAccess(AuthPrincipal principal, String projectId, boolean writable) {
  public String accountId() {
    return principal.accountId();
  }
}
