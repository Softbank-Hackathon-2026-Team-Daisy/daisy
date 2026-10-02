package com.teamdaisy.server.project.web;

import com.fasterxml.jackson.databind.JsonNode;
import com.teamdaisy.server.project.domain.Target;
import java.time.Instant;
import java.time.format.DateTimeParseException;

/**
 * 배포할 수 있는 대상 하나예요 (WR-04). 소비자 계약은 {@code ios/SPEC.md} 406행이에요.
 *
 * <p>A-02 는 "지금 어떻게 떠 있나", 이 응답은 "어디에 배포할 수 있나" 예요.
 *
 * @param reuse 인프라가 보고한 재사용 판정. 보고가 없으면 통째로 null 이에요 — {@code available: false} 로 꾸미면 "재사용 불가로 확인됨"
 *     처럼 읽혀요
 */
public record TargetResponse(
    String targetId, String type, String name, Reuse reuse, Connection connection) {

  public record Reuse(Boolean available, String scriptId, String reason, Instant assessedAt) {}

  /**
   * @param state {@code ok}·{@code failed}·{@code unknown}. DB 값을 소비자 값으로 바꿔요
   * @param checkedAt 연결을 확인한 시각. 확인한 적 없으면 null 이에요
   */
  public record Connection(String state, Instant checkedAt) {}

  public static TargetResponse of(Target target) {
    return new TargetResponse(
        target.id(),
        target.environmentType(),
        target.name(),
        reuse(target.reuseAssessment()),
        new Connection(connectionState(target.connectionState()), target.connectionCheckedAt()));
  }

  /**
   * DB 연결 상태를 소비자 값으로 바꿔요 (S1: DB enum 을 그대로 노출하지 않음).
   *
   * <p>모르는 값은 꾸미지 않고 그대로 보내요. 소비자가 모르는 값을 보는 게, 아는 값으로 둔갑한 것보다 안전해요.
   */
  static String connectionState(String stored) {
    if (stored == null) {
      return "unknown";
    }
    return switch (stored) {
      case "connected" -> "ok";
      case "disconnected" -> "failed";
      default -> stored;
    };
  }

  /** 저장된 판정이 모양과 다르면 그 대상의 {@code reuse} 만 비워요. 목록 전체를 실패시키지 않아요. */
  static Reuse reuse(JsonNode stored) {
    if (stored == null || !stored.isObject()) {
      return null;
    }
    JsonNode available = stored.get("available");
    if (available == null || !available.isBoolean()) {
      return null;
    }
    return new Reuse(
        available.booleanValue(),
        text(stored, "script_id"),
        text(stored, "reason"),
        instant(stored, "assessed_at"));
  }

  private static String text(JsonNode node, String key) {
    JsonNode value = node.get(key);
    return value != null && value.isTextual() ? value.asText() : null;
  }

  private static Instant instant(JsonNode node, String key) {
    String value = text(node, key);
    if (value == null) {
      return null;
    }
    try {
      return Instant.parse(value);
    } catch (DateTimeParseException exception) {
      return null;
    }
  }
}
