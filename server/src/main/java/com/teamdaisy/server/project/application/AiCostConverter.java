package com.teamdaisy.server.project.application;

import java.math.BigDecimal;
import java.math.RoundingMode;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

/**
 * AI 비용을 고정 환율로 원화로 바꿔요 (9/29 결정: USD 를 배포 단위로 먼저 더한 뒤 한 번만 환산·반올림).
 *
 * <p>환율 숫자는 아직 정하지 않았어요. 설정이 없으면 원화를 만들지 않고 null 로 둬요. 잘못된 값이면 기동하지 않아요 — 발표 중에 틀린 금액을 보여주는 것보다 낫다고
 * 봤어요.
 */
@Component
public class AiCostConverter {
  private final BigDecimal krwPerUsd;

  public AiCostConverter(@Value("${daisy.ai.krw-per-usd:}") String krwPerUsd) {
    this.krwPerUsd = parse(krwPerUsd);
  }

  /** 설정된 환율이에요. 없으면 null 이에요. */
  public BigDecimal rate() {
    return krwPerUsd;
  }

  /** USD 합을 원 단위 정수로 바꿔요. 합이나 환율이 없으면 null 이에요. */
  public Long toKrw(BigDecimal usd) {
    return toKrw(usd, krwPerUsd);
  }

  static Long toKrw(BigDecimal usd, BigDecimal rate) {
    if (usd == null || rate == null) {
      return null;
    }
    return usd.multiply(rate).setScale(0, RoundingMode.HALF_UP).longValueExact();
  }

  static BigDecimal parse(String value) {
    if (value == null || value.isBlank()) {
      return null;
    }
    BigDecimal rate;
    try {
      rate = new BigDecimal(value.trim());
    } catch (NumberFormatException exception) {
      throw new IllegalStateException("daisy.ai.krw-per-usd 는 숫자여야 해요");
    }
    if (rate.signum() <= 0) {
      throw new IllegalStateException("daisy.ai.krw-per-usd 는 0 보다 커야 해요");
    }
    return rate;
  }
}
