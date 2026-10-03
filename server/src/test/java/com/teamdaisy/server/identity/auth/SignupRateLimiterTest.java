package com.teamdaisy.server.identity.auth;

import static org.assertj.core.api.Assertions.assertThat;

import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.time.ZoneId;
import java.time.ZoneOffset;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

class SignupRateLimiterTest {
  /** 테스트가 시간을 직접 옮기는 시계예요. */
  private static final class MovableClock extends Clock {
    private Instant now = Instant.parse("2026-10-03T00:00:00Z");

    void advance(Duration duration) {
      now = now.plus(duration);
    }

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

  @Test
  @DisplayName("IP 별로 10분 창 안에서 5번까지 받고, 가장 오래된 시도가 창을 벗어나면 다시 받아요")
  void slidingWindowPerIp() {
    MovableClock clock = new MovableClock();
    SignupRateLimiter limiter = new SignupRateLimiter(clock);

    assertThat(limiter.tryAcquire("a")).isTrue();
    clock.advance(Duration.ofMinutes(5));
    for (int i = 0; i < 4; i++) {
      assertThat(limiter.tryAcquire("a")).isTrue();
    }
    assertThat(limiter.tryAcquire("a")).isFalse();
    assertThat(limiter.tryAcquire("b")).isTrue();

    // 첫 시도가 창을 벗어나면 한 번 더 받아요. 거절된 시도는 세지 않아요.
    clock.advance(Duration.ofMinutes(5));
    assertThat(limiter.tryAcquire("a")).isTrue();
    assertThat(limiter.tryAcquire("a")).isFalse();
  }
}
