package com.teamdaisy.server.push;

import com.fasterxml.jackson.databind.ObjectMapper;
import java.nio.charset.StandardCharsets;
import java.security.GeneralSecurityException;
import java.security.KeyFactory;
import java.security.PrivateKey;
import java.security.Signature;
import java.security.spec.PKCS8EncodedKeySpec;
import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.util.Base64;
import java.util.LinkedHashMap;
import java.util.Map;

/**
 * APNs 토큰 인증용 ES256 JWT 예요.
 *
 * <p>헤더 {@code {alg: ES256, kid}}, 클레임 {@code {iss: team id, iat}} 이에요. APNs 는 20분보다 자주 바꾸면 거절하고
 * 1시간이 지나면 만료라서 50분마다 새로 서명해요. 서명은 JDK 의 {@code SHA256withECDSAinP1363Format} (r||s 64바이트)을 써요.
 */
final class ApnsJwt {
  static final Duration REFRESH = Duration.ofMinutes(50);
  private static final ObjectMapper JSON = new ObjectMapper();
  private static final Base64.Encoder B64 = Base64.getUrlEncoder().withoutPadding();

  private final PrivateKey key;
  private final String keyId;
  private final String teamId;
  private final Clock clock;
  private String token;
  private Instant issuedAt;

  ApnsJwt(PrivateKey key, String keyId, String teamId, Clock clock) {
    this.key = key;
    this.keyId = keyId;
    this.teamId = teamId;
    this.clock = clock;
  }

  /** 캐시한 토큰을 주고, 50분이 지났으면 새로 서명해요. */
  synchronized String current() {
    Instant now = clock.instant();
    if (token == null || !now.isBefore(issuedAt.plus(REFRESH))) {
      token = sign(now);
      issuedAt = now;
    }
    return token;
  }

  /** APNs 가 만료됐다고 답하면 다음 요청에서 새로 서명해요. */
  synchronized void invalidate() {
    token = null;
  }

  String sign(Instant iat) {
    Map<String, Object> header = new LinkedHashMap<>();
    header.put("alg", "ES256");
    header.put("kid", keyId);
    Map<String, Object> claims = new LinkedHashMap<>();
    claims.put("iss", teamId);
    claims.put("iat", iat.getEpochSecond());
    try {
      String input =
          part(JSON.writeValueAsBytes(header)) + "." + part(JSON.writeValueAsBytes(claims));
      Signature signer = Signature.getInstance("SHA256withECDSAinP1363Format");
      signer.initSign(key);
      signer.update(input.getBytes(StandardCharsets.US_ASCII));
      return input + "." + part(signer.sign());
    } catch (Exception e) {
      // 예외 메시지에 키 정보가 섞이지 않게 형식 이름만 남겨요.
      throw new IllegalStateException("apns_jwt_sign_failed " + e.getClass().getSimpleName());
    }
  }

  private static String part(byte[] bytes) {
    return B64.encodeToString(bytes);
  }

  /**
   * {@code .p8} PEM(PKCS#8) 문자열을 EC 개인 키로 읽어요.
   *
   * <p>환경변수 한 줄에 넣을 수 있게 {@code \n} 이스케이프도 받아요.
   */
  static PrivateKey parsePem(String pem) throws GeneralSecurityException {
    String body =
        pem.replace("\\n", "\n")
            .replaceAll("-----(BEGIN|END) [A-Z ]*PRIVATE KEY-----", "")
            .replaceAll("\\s", "");
    byte[] der;
    try {
      der = Base64.getDecoder().decode(body);
    } catch (IllegalArgumentException e) {
      throw new GeneralSecurityException("invalid base64");
    }
    return KeyFactory.getInstance("EC").generatePrivate(new PKCS8EncodedKeySpec(der));
  }
}
