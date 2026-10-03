package com.teamdaisy.server.push;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.security.GeneralSecurityException;
import java.security.PrivateKey;
import java.time.Clock;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.scheduling.annotation.EnableScheduling;

/**
 * APNs 설정이에요. 값은 전부 환경변수로 받고 {@code application.yml} 에는 두지 않아요.
 *
 * <p>키({@code DAISY_APNS_KEY} 또는 {@code DAISY_APNS_KEY_PATH})와 {@code DAISY_APNS_KEY_ID} 가 둘 다 있을
 * 때만 켜져요. 없으면 발송기는 커서만 앞으로 옮겨서, 나중에 키를 넣어도 지난 이벤트가 몰려 나가지 않아요. 스케줄링은 Jenkins 워커가 꺼져 있으면 켜지지 않아서
 * 여기서도 켜요.
 */
@Configuration
@EnableScheduling
public class PushConfiguration {
  private static final Logger LOG = LoggerFactory.getLogger(PushConfiguration.class);

  @Bean
  ApnsSender apnsSender(
      @Value("${DAISY_APNS_KEY:}") String key,
      @Value("${DAISY_APNS_KEY_PATH:}") String keyPath,
      @Value("${DAISY_APNS_KEY_ID:}") String keyId,
      @Value("${DAISY_APNS_TEAM_ID:X5F5WM2H6M}") String teamId,
      @Value("${DAISY_APNS_TOPIC:com.teamdaisy.daisy}") String topic,
      Clock clock) {
    return create(key, keyPath, keyId, teamId, topic, clock);
  }

  /** 키 원문·경로는 로그에 남기지 않아요. 왜 꺼졌는지만 한 번 남겨요. */
  static ApnsSender create(
      String key, String keyPath, String keyId, String teamId, String topic, Clock clock) {
    String pem = key;
    if (blank(pem) && !blank(keyPath)) {
      try {
        pem = Files.readString(Path.of(keyPath.trim()));
      } catch (IOException | RuntimeException e) {
        LOG.warn("push_disabled reason=key_file_unreadable");
        return ApnsSender.disabled();
      }
    }
    if (blank(pem) || blank(keyId)) {
      LOG.info("push_disabled reason=not_configured");
      return ApnsSender.disabled();
    }
    PrivateKey privateKey;
    try {
      privateKey = ApnsJwt.parsePem(pem);
    } catch (GeneralSecurityException | RuntimeException e) {
      LOG.warn("push_disabled reason=key_invalid");
      return ApnsSender.disabled();
    }
    LOG.info("push_enabled key_id={} team_id={} topic={}", keyId.trim(), teamId, topic);
    return new ApnsClient(
        new ApnsJwt(privateKey, keyId.trim(), teamId.trim(), clock), topic.trim());
  }

  private static boolean blank(String value) {
    return value == null || value.isBlank();
  }
}
