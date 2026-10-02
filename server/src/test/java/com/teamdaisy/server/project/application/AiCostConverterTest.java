package com.teamdaisy.server.project.application;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import java.math.BigDecimal;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

/** AI 비용 원화 환산 규칙을 고정해요 (server/SPEC.md 「배포 plan 조회 A-05」). */
class AiCostConverterTest {

  @Test
  @DisplayName("USD 합에 환율을 곱해 원 단위로 한 번만 반올림해요")
  void convertsOnceWithHalfUp() {
    BigDecimal rate = new BigDecimal("1400");
    // 0.0012345 + 0.0010000 = 0.0022345 USD → 3.1283원 → 3원
    assertThat(AiCostConverter.toKrw(new BigDecimal("0.0022345"), rate)).isEqualTo(3L);
    // 0.00025 USD → 0.35원 → 0원, 0.0025 → 3.5원 → 4원 (HALF_UP)
    assertThat(AiCostConverter.toKrw(new BigDecimal("0.00025"), rate)).isEqualTo(0L);
    assertThat(AiCostConverter.toKrw(new BigDecimal("0.0025"), rate)).isEqualTo(4L);
  }

  @Test
  @DisplayName("합이나 환율이 없으면 원화를 만들지 않아요")
  void missingValuesStayNull() {
    assertThat(AiCostConverter.toKrw(null, new BigDecimal("1400"))).isNull();
    assertThat(AiCostConverter.toKrw(new BigDecimal("1"), null)).isNull();
    assertThat(new AiCostConverter("").rate()).isNull();
    assertThat(new AiCostConverter("  ").toKrw(new BigDecimal("1"))).isNull();
  }

  @Test
  @DisplayName("숫자가 아니거나 0 이하인 환율이면 기동하지 않아요")
  void invalidRateFailsFast() {
    assertThatThrownBy(() -> new AiCostConverter("abc")).isInstanceOf(IllegalStateException.class);
    assertThatThrownBy(() -> new AiCostConverter("0")).isInstanceOf(IllegalStateException.class);
    assertThatThrownBy(() -> new AiCostConverter("-1")).isInstanceOf(IllegalStateException.class);
    assertThat(new AiCostConverter("1380.5").rate()).isEqualByComparingTo("1380.5");
  }
}
