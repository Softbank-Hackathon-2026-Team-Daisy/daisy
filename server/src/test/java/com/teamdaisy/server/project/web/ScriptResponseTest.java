package com.teamdaisy.server.project.web;

import static org.assertj.core.api.Assertions.assertThat;

import com.teamdaisy.server.project.application.ScriptReader.ScriptRow;
import java.time.Instant;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

/** WR-10 한 줄 변환을 고정해요 (server/SPEC.md 「스크립트 목록 WR-10」). */
class ScriptResponseTest {
  private static final Instant NOW = Instant.parse("2026-10-02T05:00:00Z");
  private static final Instant AT = Instant.parse("2026-10-02T01:00:00Z");

  private static ScriptRow row(
      Boolean reused, Instant unavailable, Instant expires, long plans, Integer risks) {
    return new ScriptRow(
        "scr_1", "tgt_aws", "aws", 2, AT, unavailable, expires, reused, 2, 3, AT, plans, risks);
  }

  @Test
  @DisplayName("버전은 s+숫자, 처음 검증이 재사용 아니면 ai_generated, plan 이 있으면 plan·위험 수")
  void mapsFields() {
    var r = ScriptResponse.of(row(false, null, null, 1, 2), NOW);

    assertThat(r.version()).isEqualTo("s2");
    assertThat(r.origin()).isEqualTo("ai_generated");
    assertThat(r.attempt()).isEqualTo(2);
    assertThat(r.validation()).isEqualTo(new ScriptResponse.Validation(true, true, 2));
    assertThat(r.status()).isEqualTo("verified");
    assertThat(r.reuseCount()).isEqualTo(3);
    assertThat(r.createdAt()).isEqualTo(AT);
  }

  @Test
  @DisplayName("원본을 못 쓰거나 보관 기한이 지났으면 discarded, plan 이 없으면 plan false·위험 null")
  void discardedAndNoPlan() {
    assertThat(ScriptResponse.of(row(true, AT, null, 0, null), NOW).status())
        .isEqualTo("discarded");
    assertThat(ScriptResponse.of(row(true, null, NOW, 0, null), NOW).status())
        .isEqualTo("discarded");
    assertThat(ScriptResponse.of(row(true, null, NOW.plusSeconds(1), 0, null), NOW).status())
        .isEqualTo("verified");

    var noPlan = ScriptResponse.of(row(true, null, null, 0, null), NOW);
    assertThat(noPlan.origin()).isEqualTo("reused");
    assertThat(noPlan.validation()).isEqualTo(new ScriptResponse.Validation(true, false, null));
    assertThat(ScriptResponse.of(row(null, null, null, 0, null), NOW).origin()).isNull();
  }

  @Test
  @DisplayName("시도 0 은 A-04 와 같이 null 이에요 (S2)")
  void zeroAttemptIsNull() {
    var zero =
        new ScriptRow("scr_1", "tgt_aws", "aws", 1, AT, null, null, false, 0, 0, null, 0, null);
    assertThat(ScriptResponse.of(zero, NOW).attempt()).isNull();
  }

  @Test
  @DisplayName("재사용 아니고 생성 시도가 있어야 ai_generated, 기준 모듈·출처 미확인은 null 이에요 (#68)")
  void originNeedsGenerationEvidence() {
    assertThat(ScriptResponse.origin(true, 0)).isEqualTo("reused");
    assertThat(ScriptResponse.origin(false, 2)).isEqualTo("ai_generated");
    assertThat(ScriptResponse.origin(false, 0)).isNull(); // USE_AI=false 기준 모듈
    assertThat(ScriptResponse.origin(false, null)).isNull();
    assertThat(ScriptResponse.origin(null, 2)).isNull();
    var reference =
        new ScriptRow("scr_ref", "tgt_aws", "aws", 1, AT, null, null, false, 0, 0, null, 0, null);
    assertThat(ScriptResponse.of(reference, NOW).origin()).isNull();
  }
}
