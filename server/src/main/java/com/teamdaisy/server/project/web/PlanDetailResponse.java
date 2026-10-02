package com.teamdaisy.server.project.web;

import com.fasterxml.jackson.databind.JsonNode;
import com.teamdaisy.server.project.application.DeploymentPlanReader.PlanRow;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.List;
import java.util.Set;

/**
 * 대상 하나의 리소스 전체 목록이에요 (WR-06, {@code ?detail=resources}). 소비자 모델은 {@code web/src/api/types.ts} 의
 * {@code PlanDetail} 이에요.
 *
 * @param planText 서버가 plan 원문을 보관하지 않아 null 이에요
 */
public record PlanDetailResponse(String targetId, List<Resource> resources, String planText) {

  /** 리소스 한 줄이에요. {@code action} 은 create·update·delete·replace 중 하나예요. */
  public record Resource(String address, String action) {}

  static PlanDetailResponse of(PlanRow row) {
    List<Resource> resources = new ArrayList<>();
    if (row.resources() != null) {
      for (JsonNode resource : row.resources()) {
        String action = action(resource.path("actions"));
        JsonNode address = resource.get("address");
        if (action != null && address != null && address.isTextual()) {
          resources.add(new Resource(address.asText(), action));
        }
      }
    }
    return new PlanDetailResponse(row.targetId(), resources, null);
  }

  /**
   * Terraform 의 {@code actions} 배열을 화면 값 하나로 바꿔요.
   *
   * <p>지우고 다시 만드는 교체는 순서와 상관없이 replace 예요. read·no-op 만 있으면 바뀌는 것이 아니라 null 이고 목록에서 빠져요.
   */
  static String action(JsonNode actions) {
    Set<String> values = new HashSet<>();
    for (JsonNode value : actions) {
      if (value.isTextual()) {
        values.add(value.asText());
      }
    }
    if (values.contains("delete") && values.contains("create")) {
      return "replace";
    }
    for (String action : List.of("delete", "create", "update")) {
      if (values.contains(action)) {
        return action;
      }
    }
    return null;
  }
}
