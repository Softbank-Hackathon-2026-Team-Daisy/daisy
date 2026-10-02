package com.teamdaisy.server.identity.auth;

import com.teamdaisy.server.common.error.DaisyException;
import com.teamdaisy.server.common.error.ErrorCode;
import io.jsonwebtoken.Claims;
import io.jsonwebtoken.JwtException;
import io.jsonwebtoken.Jwts;
import io.jsonwebtoken.security.Keys;
import java.nio.charset.StandardCharsets;
import java.time.Instant;
import java.util.Date;
import javax.crypto.SecretKey;
import org.springframework.stereotype.Service;

/**
 * Bearer 토큰을 만들고 검증해요.
 *
 * <p>별도 토큰 테이블을 두지 않아요 (database-design.md 5.1). 서명과 만료만으로 검증하고, 계정의 현재 역할·활성 여부는 토큰이 아니라 DB 에서 다시
 * 읽어요.
 */
@Service
public class TokenService {
  private static final String CLAIM_USERNAME = "username";

  private final SecretKey key;
  private final AuthProperties properties;

  public TokenService(AuthProperties properties) {
    this.properties = properties;
    this.key = Keys.hmacShaKeyFor(properties.secret().getBytes(StandardCharsets.UTF_8));
  }

  /** 계정 ID 를 주체로 하는 토큰을 발급해요. */
  public IssuedToken issue(String accountId, String username, Instant now) {
    Instant expiresAt = now.plus(properties.tokenTtl());
    String token =
        Jwts.builder()
            .issuer(properties.issuer())
            .subject(accountId)
            .claim(CLAIM_USERNAME, username)
            .issuedAt(Date.from(now))
            .expiration(Date.from(expiresAt))
            .signWith(key)
            .compact();
    return new IssuedToken(token, expiresAt);
  }

  /**
   * 토큰에서 계정 ID 를 꺼내요. 서명·만료·발급자가 맞지 않으면 401 이에요.
   *
   * <p>여기서 역할을 꺼내지 않아요. 토큰을 발급한 뒤 권한이 바뀌었을 수 있어서, 역할은 호출하는 쪽이 DB 에서 읽어요.
   */
  public String accountIdOf(String token) {
    try {
      Claims claims =
          Jwts.parser()
              .verifyWith(key)
              .requireIssuer(properties.issuer())
              .build()
              .parseSignedClaims(token)
              .getPayload();
      String subject = claims.getSubject();
      if (subject == null || subject.isBlank()) {
        throw new DaisyException(ErrorCode.UNAUTHENTICATED);
      }
      return subject;
    } catch (JwtException | IllegalArgumentException exception) {
      // 토큰 원문·파싱 실패 사유를 응답에 담지 않아요.
      throw new DaisyException(ErrorCode.UNAUTHENTICATED);
    }
  }

  public record IssuedToken(String value, Instant expiresAt) {}
}
