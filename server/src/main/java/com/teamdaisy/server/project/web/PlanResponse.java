package com.teamdaisy.server.project.web;

import com.fasterxml.jackson.databind.JsonNode;
import com.teamdaisy.server.project.application.AiCostConverter;
import com.teamdaisy.server.project.application.DeploymentPlanReader.PlanRow;
import com.teamdaisy.server.project.application.DeploymentPlanReader.UsageTotals;
import java.math.BigDecimal;
import java.util.ArrayList;
import java.util.List;

/**
 * 배포 plan 요약이에요 (A-05). 소비자 모델은 {@code ios/SPEC.md}·{@code web/src/api/types.ts} 의 {@code Plan}
 * 이에요.
 *
 * <p>현재 plan 이 있는 대상만 나와요. 승인할 대상과 approval ID 는 A-04 {@code pending_approvals} 가 기준이에요.
 */
public record PlanResponse(String deploymentId, List<Target> targets, AiUsage aiUsage) {

  /**
   * 대상 하나의 plan 이에요.
   *
   * @param summary 한 줄 요약을 만드는 원천이 없어 null 이에요
   * @param planText 서버가 plan 원문을 보관하지 않아 null 이에요
   */
  public record Target(
      String targetId,
      Counts counts,
      boolean hasDelete,
      List<Risk> risks,
      String summary,
      String planText) {}

  public record Counts(int create, int update, int delete) {}

  public record Risk(String level, String rule, String resource, String message) {}

  /**
   * 이 배포의 AI 사용량 합계예요. 확인하지 못한 값은 0 이 아니라 null 이에요.
   *
   * @param exchangeRate 적용한 고정 환율(원/USD). 설정이 없으면 null 이에요
   * @param estimated 원화가 고정 환율 환산이라 {@code cost_krw} 가 있으면 늘 true 예요
   * @param unknownCalls 토큰이나 비용을 확인하지 못한 호출 수예요
   */
  public record AiUsage(
      long calls,
      Long tokens,
      Long costKrw,
      BigDecimal exchangeRate,
      boolean estimated,
      long unknownCalls) {}

  public static PlanResponse of(
      String deploymentId, List<PlanRow> plans, UsageTotals usage, AiCostConverter cost) {
    return new PlanResponse(
        deploymentId, plans.stream().map(PlanResponse::target).toList(), aiUsage(usage, cost));
  }

  static Target target(PlanRow row) {
    JsonNode summary = row.summary();
    JsonNode counts = summary == null ? null : summary.path("counts");
    return new Target(
        row.targetId(),
        new Counts(count(counts, "create"), count(counts, "update"), count(counts, "delete")),
        summary != null && summary.path("has_delete").asBoolean(false),
        risks(summary),
        null,
        null);
  }

  static AiUsage aiUsage(UsageTotals usage, AiCostConverter cost) {
    Long krw = cost.toKrw(usage.costUsd());
    return new AiUsage(
        usage.calls(), usage.tokens(), krw, cost.rate(), krw != null, usage.unknownCalls());
  }

  private static int count(JsonNode counts, String name) {
    return counts == null ? 0 : counts.path(name).asInt(0);
  }

  private static List<Risk> risks(JsonNode summary) {
    List<Risk> risks = new ArrayList<>();
    if (summary == null) {
      return risks;
    }
    for (JsonNode risk : summary.path("risks")) {
      risks.add(
          new Risk(
              text(risk, "level"),
              text(risk, "rule"),
              text(risk, "resource"),
              text(risk, "message")));
    }
    return risks;
  }

  private static String text(JsonNode node, String key) {
    JsonNode value = node.get(key);
    return value != null && value.isTextual() ? value.asText() : null;
  }
}
