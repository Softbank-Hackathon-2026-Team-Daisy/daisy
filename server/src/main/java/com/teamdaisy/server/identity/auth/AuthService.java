package com.teamdaisy.server.identity.auth;

import com.teamdaisy.server.common.error.DaisyException;
import com.teamdaisy.server.common.error.ErrorCode;
import com.teamdaisy.server.identity.domain.Account;
import com.teamdaisy.server.identity.domain.AccountRepository;
import java.time.Clock;
import java.time.Instant;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/** 로그인과 토큰 주체 확인을 담당해요. */
@Service
@Transactional(readOnly = true)
public class AuthService {
  private final AccountRepository accounts;
  private final PasswordEncoder passwordEncoder;
  private final TokenService tokens;
  private final Clock clock;

  public AuthService(
      AccountRepository accounts,
      PasswordEncoder passwordEncoder,
      TokenService tokens,
      Clock clock) {
    this.accounts = accounts;
    this.passwordEncoder = passwordEncoder;
    this.tokens = tokens;
    this.clock = clock;
  }

  /**
   * 아이디·비밀번호를 확인하고 토큰을 발급해요.
   *
   * <p>아이디가 없는 경우와 비밀번호가 틀린 경우를 같은 응답으로 돌려줘요. 어느 쪽인지 알려주면 계정 존재 여부가 샙니다.
   */
  public LoginResult login(String username, String rawPassword) {
    Account account =
        accounts
            .findByUsername(username)
            .orElseThrow(() -> new DaisyException(ErrorCode.UNAUTHENTICATED));
    if (!account.isActive() || !passwordEncoder.matches(rawPassword, account.passwordHash())) {
      throw new DaisyException(ErrorCode.UNAUTHENTICATED);
    }
    Instant now = clock.instant();
    TokenService.IssuedToken token = tokens.issue(account.id(), account.username(), now);
    return new LoginResult(token.value(), token.expiresAt(), account.role());
  }

  /**
   * 토큰에서 현재 주체를 읽어요.
   *
   * <p>역할과 활성 여부는 토큰이 아니라 DB 에서 다시 읽어요. 발급 뒤에 권한이 바뀌거나 계정이 비활성화됐을 수 있어요.
   */
  public AuthPrincipal resolve(String token) {
    String accountId = tokens.accountIdOf(token);
    Account account =
        accounts
            .findById(accountId)
            .orElseThrow(() -> new DaisyException(ErrorCode.UNAUTHENTICATED));
    if (!account.isActive()) {
      throw new DaisyException(ErrorCode.UNAUTHENTICATED);
    }
    return new AuthPrincipal(account.id(), account.username(), account.role());
  }

  public record LoginResult(String accessToken, Instant expiresAt, String role) {}
}
