package com.teamdaisy.server.push;

import com.teamdaisy.server.common.error.DaisyException;
import com.teamdaisy.server.common.error.ErrorCode;
import com.teamdaisy.server.identity.auth.AuthPrincipal;
import java.util.Locale;
import java.util.Set;
import java.util.regex.Pattern;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 기기 토큰 등록·해제예요 (ios/SPEC.md §6-5 P-01).
 *
 * <p>역할과 상관없이 로그인한 계정이면 돼요. 읽기 전용(viewer) 계정도 알림은 받아요.
 */
@Service
@Transactional
public class PushDeviceService {
  private static final Pattern TOKEN = Pattern.compile("[0-9a-fA-F]{32,200}");
  private static final Set<String> PLATFORMS = Set.of("ios", "macos");
  private static final Set<String> ENVS = Set.of("production", "sandbox");

  private final PushDeviceStore store;

  public PushDeviceService(PushDeviceStore store) {
    this.store = store;
  }

  public void register(AuthPrincipal principal, String token, String platform, String apnsEnv) {
    String normalized = token(token);
    require(platform != null && PLATFORMS.contains(platform));
    require(apnsEnv != null && ENVS.contains(apnsEnv));
    store.upsert(principal.accountId(), normalized, platform, apnsEnv);
  }

  public void unregister(AuthPrincipal principal, String token) {
    store.delete(principal.accountId(), token(token));
  }

  /** 대소문자만 다른 같은 토큰이 두 행이 되지 않게 소문자로 저장해요. */
  private static String token(String token) {
    require(token != null && TOKEN.matcher(token).matches());
    return token.toLowerCase(Locale.ROOT);
  }

  private static void require(boolean condition) {
    if (!condition) throw new DaisyException(ErrorCode.VALIDATION_FAILED);
  }
}
