package com.teamdaisy.server.project.web;

import static org.assertj.core.api.Assertions.assertThat;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ObjectNode;
import java.time.Instant;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

/**
 * 배포 대상 목록(WR-04)의 값 변환을 고정해요 (server/SPEC.md 「배포 대상 목록 WR-04」 T2·T3).
 *
 * <p>W-04 는 이 값으로 고를 수 있는 환경을 정해요. 연결 상태가 잘못 바뀌거나 없는 재사용 판정이 생기면 사용자가 엉뚱한 환경을 고르게 돼요.
 */
class TargetResponseTest {
  private static final ObjectMapper MAPPER = new ObjectMapper();

  @Test
  @DisplayName("연결 상태는 소비자 값(ok·failed·unknown)으로 바뀌고 모르는 값은 그대로예요")
  void connectionStateMapping() {
    assertThat(TargetResponse.connectionState("connected")).isEqualTo("ok");
    assertThat(TargetResponse.connectionState("disconnected")).isEqualTo("failed");
    assertThat(TargetResponse.connectionState("unknown")).isEqualTo("unknown");
    assertThat(TargetResponse.connectionState(null)).isEqualTo("unknown");
    assertThat(TargetResponse.connectionState("checking")).isEqualTo("checking");
  }

  @Test
  @DisplayName("재사용 판정이 없으면 available=false 가 아니라 통째로 null 이에요")
  void missingReuseIsNull() {
    assertThat(TargetResponse.reuse(null)).isNull();
  }

  @Test
  @DisplayName("정상 판정은 그대로 옮겨요")
  void reuseIsCopied() {
    ObjectNode stored =
        MAPPER
            .createObjectNode()
            .put("available", true)
            .put("script_id", "scr_7")
            .put("reason", "검증된 스크립트 있음")
            .put("assessed_at", "2026-10-02T01:00:00Z");

    TargetResponse.Reuse reuse = TargetResponse.reuse(stored);

    assertThat(reuse.available()).isTrue();
    assertThat(reuse.scriptId()).isEqualTo("scr_7");
    assertThat(reuse.reason()).isEqualTo("검증된 스크립트 있음");
    assertThat(reuse.assessedAt()).isEqualTo(Instant.parse("2026-10-02T01:00:00Z"));
  }

  @Test
  @DisplayName("모양이 틀린 판정은 그 대상의 reuse 만 null 이에요")
  void malformedReuseIsNull() {
    assertThat(TargetResponse.reuse(MAPPER.createObjectNode().put("available", "yes"))).isNull();
    assertThat(TargetResponse.reuse(MAPPER.createArrayNode())).isNull();
    assertThat(
            TargetResponse.reuse(
                    MAPPER.createObjectNode().put("available", false).put("assessed_at", "어제"))
                .assessedAt())
        .isNull();
  }
}
