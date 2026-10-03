package com.teamdaisy.server.identity.auth;

import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.util.ArrayDeque;
import java.util.Deque;
import java.util.HashMap;
import java.util.Map;
import org.springframework.stereotype.Component;

/**
 * 회원가입 시도를 클라이언트 IP 별로 10분에 5번까지만 받아요.
 *
 * <p>메모리에만 두는 간단한 슬라이딩 창이에요. 서버를 다시 띄우면 비워지고, 인스턴스끼리 공유하지 않아요. 데모 서버 한 대에서 아이디를 마구 만드는 것만 막으면 돼서예요.
 * 가입 요청은 드물어서 메서드 전체를 잠가도 충분해요.
 */
@Component
public class SignupRateLimiter {
  static final int LIMIT = 5;
  static final Duration WINDOW = Duration.ofMinutes(10);
  // 오래된 IP 기록이 쌓이지 않게, 이 개수를 넘으면 창이 지난 기록을 한 번에 지워요.
  private static final int SWEEP_THRESHOLD = 10_000;

  private final Clock clock;
  private final Map<String, Deque<Instant>> attempts = new HashMap<>();

  public SignupRateLimiter(Clock clock) {
    this.clock = clock;
  }

  /** 이번 시도를 기록해요. 창 안에서 이미 {@value #LIMIT}번을 채웠으면 기록하지 않고 false 예요. */
  public synchronized boolean tryAcquire(String clientIp) {
    Instant now = clock.instant();
    Instant cutoff = now.minus(WINDOW);
    if (attempts.size() > SWEEP_THRESHOLD) {
      attempts.values().removeIf(times -> !times.peekLast().isAfter(cutoff));
    }
    Deque<Instant> window = attempts.computeIfAbsent(clientIp, key -> new ArrayDeque<>());
    while (!window.isEmpty() && !window.peekFirst().isAfter(cutoff)) {
      window.pollFirst();
    }
    if (window.size() >= LIMIT) {
      return false;
    }
    window.addLast(now);
    return true;
  }
}
