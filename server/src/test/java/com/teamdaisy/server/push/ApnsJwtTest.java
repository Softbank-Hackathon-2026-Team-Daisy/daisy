package com.teamdaisy.server.push;

import static org.assertj.core.api.Assertions.assertThat;

import com.fasterxml.jackson.databind.ObjectMapper;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.security.KeyPair;
import java.security.KeyPairGenerator;
import java.security.Signature;
import java.security.spec.ECGenParameterSpec;
import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.time.ZoneId;
import java.time.ZoneOffset;
import java.util.Base64;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;

/** APNs JWT 서명·캐시와 키 설정을 실제 P-256 키로 확인해요. 테스트 키는 실행할 때마다 새로 만들어요. */
class ApnsJwtTest {
  private static final Instant T0 = Instant.parse("2026-10-03T00:00:00Z");
  private static final ObjectMapper JSON = new ObjectMapper();

  /** 테스트에서 시간을 움직일 수 있는 시계예요. */
  static final class MovableClock extends Clock {
    Instant now = T0;

    @Override
    public ZoneId getZone() {
      return ZoneOffset.UTC;
    }

    @Override
    public Clock withZone(ZoneId zone) {
      return this;
    }

    @Override
    public Instant instant() {
      return now;
    }
  }

  private static KeyPair keyPair() throws Exception {
    KeyPairGenerator generator = KeyPairGenerator.getInstance("EC");
    generator.initialize(new ECGenParameterSpec("secp256r1"));
    return generator.generateKeyPair();
  }

  /** Apple 이 내려주는 .p8 과 같은 PKCS#8 PEM 이에요. */
  private static String pem(KeyPair pair) {
    String body =
        Base64.getMimeEncoder(64, "\n".getBytes(StandardCharsets.US_ASCII))
            .encodeToString(pair.getPrivate().getEncoded());
    return "-----BEGIN PRIVATE KEY-----\n" + body + "\n-----END PRIVATE KEY-----\n";
  }

  @Test
  @DisplayName("ES256 서명이 공개 키로 검증되고 헤더·클레임이 APNs 형식이에요")
  void signsVerifiableToken() throws Exception {
    KeyPair pair = keyPair();
    // 환경변수 한 줄로 넣은 경우처럼 줄바꿈을 \n 글자로 바꿔도 읽혀요.
    var key = ApnsJwt.parsePem(pem(pair).replace("\n", "\\n"));
    String token = new ApnsJwt(key, "ABC123DEFG", "X5F5WM2H6M", new MovableClock()).current();

    String[] parts = token.split("\\.");
    assertThat(parts).hasSize(3);
    var decoder = Base64.getUrlDecoder();
    assertThat(JSON.readTree(decoder.decode(parts[0])))
        .isEqualTo(JSON.readTree("{\"alg\":\"ES256\",\"kid\":\"ABC123DEFG\"}"));
    assertThat(JSON.readTree(decoder.decode(parts[1])))
        .isEqualTo(JSON.readTree("{\"iss\":\"X5F5WM2H6M\",\"iat\":" + T0.getEpochSecond() + "}"));
    byte[] signature = decoder.decode(parts[2]);
    assertThat(signature).hasSize(64);
    var verifier = Signature.getInstance("SHA256withECDSAinP1363Format");
    verifier.initVerify(pair.getPublic());
    verifier.update((parts[0] + "." + parts[1]).getBytes(StandardCharsets.US_ASCII));
    assertThat(verifier.verify(signature)).isTrue();
    assertThat(token).doesNotContain("=").doesNotContain("+").doesNotContain("/");
  }

  @Test
  @DisplayName("토큰은 50분 동안 재사용하고, 지나거나 만료 응답을 받으면 새로 서명해요")
  void cachesForFiftyMinutes() throws Exception {
    var clock = new MovableClock();
    var jwt = new ApnsJwt(keyPair().getPrivate(), "KEY", "TEAM", clock);
    String first = jwt.current();

    clock.now = T0.plus(Duration.ofMinutes(49));
    assertThat(jwt.current()).isSameAs(first);

    clock.now = T0.plus(ApnsJwt.REFRESH);
    String second = jwt.current();
    assertThat(second).isNotEqualTo(first);
    assertThat(claims(second).path("iat").asLong()).isEqualTo(clock.now.getEpochSecond());

    clock.now = clock.now.plusSeconds(60);
    jwt.invalidate();
    assertThat(claims(jwt.current()).path("iat").asLong()).isEqualTo(clock.now.getEpochSecond());
  }

  private static com.fasterxml.jackson.databind.JsonNode claims(String token) throws Exception {
    return JSON.readTree(Base64.getUrlDecoder().decode(token.split("\\.")[1]));
  }

  @Test
  @DisplayName("키나 키 ID 가 없거나 키가 깨졌으면 꺼진 발송기, 둘 다 있으면 켜진 발송기예요")
  void configurationEnablesOnlyWithKeyAndKeyId(@TempDir Path dir) throws Exception {
    var clock = Clock.systemUTC();
    String pem = pem(keyPair());
    assertThat(PushConfiguration.create("", "", "", "TEAM", "topic", clock).enabled()).isFalse();
    assertThat(PushConfiguration.create(pem, "", "", "TEAM", "topic", clock).enabled()).isFalse();
    assertThat(PushConfiguration.create("", "", "KEY", "TEAM", "topic", clock).enabled()).isFalse();
    assertThat(PushConfiguration.create("not a key", "", "KEY", "TEAM", "topic", clock).enabled())
        .isFalse();
    assertThat(
            PushConfiguration.create(
                    "", dir.resolve("missing.p8").toString(), "KEY", "T", "t", clock)
                .enabled())
        .isFalse();
    assertThat(PushConfiguration.create(pem, "", "KEY", "TEAM", "topic", clock).enabled()).isTrue();
    Path file = Files.writeString(dir.resolve("AuthKey.p8"), pem);
    assertThat(
            PushConfiguration.create("", file.toString(), "KEY", "TEAM", "topic", clock).enabled())
        .isTrue();
  }

  @Test
  @DisplayName("APNs 오류 본문에서 reason 을 읽고, 기기를 끌 응답만 골라요")
  void readsRejectionReason() {
    assertThat(ApnsClient.reason("{\"reason\":\"BadDeviceToken\"}")).isEqualTo("BadDeviceToken");
    assertThat(ApnsClient.reason("")).isNull();
    assertThat(ApnsClient.reason("<html>")).isNull();
    assertThat(new ApnsSender.Result(400, "BadDeviceToken").deviceGone()).isTrue();
    assertThat(new ApnsSender.Result(400, "DeviceTokenNotForTopic").deviceGone()).isTrue();
    assertThat(new ApnsSender.Result(410, "Unregistered").deviceGone()).isTrue();
    assertThat(new ApnsSender.Result(400, "BadCollapseId").deviceGone()).isFalse();
    assertThat(new ApnsSender.Result(403, "InvalidProviderToken").deviceGone()).isFalse();
    assertThat(new ApnsSender.Result(200, null).ok()).isTrue();
  }
}
