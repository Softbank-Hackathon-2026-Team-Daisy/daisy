package com.teamdaisy.server.identity.auth;

import java.time.Duration;
import org.springframework.boot.context.properties.ConfigurationProperties;

/**
 * 인증 설정이에요. 비밀값은 환경변수로만 받아요 (server/AGENTS.md).
 *
 * @param secret 토큰 서명 키. HS256 이라 32바이트 이상이어야 해요
 * @param tokenTtl 토큰 유효 기간
 * @param issuer 토큰 발급자
 */
@ConfigurationProperties(prefix = "daisy.auth")
public record AuthProperties(String secret, Duration tokenTtl, String issuer) {
  public AuthProperties {
    if (secret == null || secret.isBlank()) {
      throw new IllegalStateException("daisy.auth.secret 이 필요해요. DAISY_AUTH_SECRET 을 설정해 주세요.");
    }
    if (secret.getBytes(java.nio.charset.StandardCharsets.UTF_8).length < 32) {
      throw new IllegalStateException("daisy.auth.secret 은 32바이트 이상이어야 해요.");
    }
    tokenTtl = tokenTtl == null ? Duration.ofHours(12) : tokenTtl;
    issuer = issuer == null || issuer.isBlank() ? "daisy" : issuer;
  }
}
