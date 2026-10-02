package com.teamdaisy.server.project.web;

import static org.assertj.core.api.Assertions.assertThat;

import com.teamdaisy.server.project.application.AiCostConverter;
import com.teamdaisy.server.project.application.AiUsageReader.CallRow;
import com.teamdaisy.server.project.web.AiUsageController.AiUsageCall;
import java.math.BigDecimal;
import java.time.Instant;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

/** WR-11 호출 한 줄 변환을 고정해요 (server/SPEC.md 「AI 호출별 기록 WR-11」). */
class AiUsageCallTest {
  private static final Instant AT = Instant.parse("2026-10-02T01:00:00Z");

  private static CallRow row(Long tokens, String usd, String status) {
    return new CallRow(
        AT, "dep_1", "tgt_aws", "fix", 2, tokens, usd == null ? null : new BigDecimal(usd), status);
  }

  @Test
  @DisplayName("줄마다 고정 환율로 원화 반올림하고, 모르는 값은 null 이에요")
  void convertsPerRow() {
    var cost = new AiCostConverter("1400");
    var known = AiUsageCall.of(row(1860L, "0.0343", "succeeded"), cost);
    assertThat(known.tokens()).isEqualTo(1860L);
    assertThat(known.costKrw()).isEqualTo(48L); // 0.0343 × 1400 = 48.02
    assertThat(known.status()).isEqualTo("succeeded");
    assertThat(known.note()).isNull();

    var unknown = AiUsageCall.of(row(null, null, "failed"), cost);
    assertThat(unknown.tokens()).isNull();
    assertThat(unknown.costKrw()).isNull();
    assertThat(unknown.attempt()).isEqualTo(2);
  }

  @Test
  @DisplayName("환율 설정이 없으면 원화는 null 이에요")
  void noRateNoKrw() {
    var call = AiUsageCall.of(row(100L, "1", "succeeded"), new AiCostConverter(""));
    assertThat(call.costKrw()).isNull();
    assertThat(call.tokens()).isEqualTo(100L);
  }
}
