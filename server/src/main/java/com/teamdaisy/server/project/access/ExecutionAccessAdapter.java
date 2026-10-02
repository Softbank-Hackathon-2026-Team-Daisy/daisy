package com.teamdaisy.server.project.access;

import com.teamdaisy.server.common.error.DaisyException;
import com.teamdaisy.server.common.error.ErrorCode;
import com.teamdaisy.server.deployment.application.ExecutionAccess;
import com.teamdaisy.server.identity.auth.AuthPrincipal;
import com.teamdaisy.server.identity.domain.Account;
import com.teamdaisy.server.identity.domain.AccountRepository;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;

/**
 * 실행 서비스의 접근 검사를 {@link ProjectAccessService} 로 연결해요.
 *
 * <p>실행 서비스는 계정 ID 만 알고 제 인증 타입을 몰라요. 그래서 계정 ID 로 계정을 다시 읽어 역할과 활성 여부를 확인한 뒤 판정을 위임해요. 역할을 요청마다 DB
 * 에서 읽는 원칙과 같아요 (server/SPEC.md).
 *
 * <p>호출한 쪽의 트랜잭션에 참여하고 읽기만 해요. 잠금을 걸지 않고 외부 호출도 하지 않아요.
 */
@Component
@Transactional(readOnly = true)
public class ExecutionAccessAdapter implements ExecutionAccess {
  private final AccountRepository accounts;
  private final ProjectAccessService access;

  public ExecutionAccessAdapter(AccountRepository accounts, ProjectAccessService access) {
    this.accounts = accounts;
    this.access = access;
  }

  @Override
  public void requireRead(String actorId, String projectId) {
    access.requireRead(principal(actorId), projectId);
  }

  @Override
  public void requireWrite(String actorId, String projectId) {
    access.requireWrite(principal(actorId), projectId);
  }

  /**
   * 계정 ID 로 현재 주체를 만들어요.
   *
   * <p>인증 필터를 통과한 뒤 같은 요청 안에서 계정이 비활성화될 수 있어요. 없거나 비활성인 계정은 401 이에요.
   */
  private AuthPrincipal principal(String actorId) {
    if (actorId == null || actorId.isBlank()) {
      throw new DaisyException(ErrorCode.UNAUTHENTICATED);
    }
    Account account =
        accounts
            .findById(actorId)
            .filter(Account::isActive)
            .orElseThrow(() -> new DaisyException(ErrorCode.UNAUTHENTICATED));
    return new AuthPrincipal(account.id(), account.username(), account.role());
  }
}
