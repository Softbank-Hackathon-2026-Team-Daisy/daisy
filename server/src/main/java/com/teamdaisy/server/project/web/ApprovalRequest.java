package com.teamdaisy.server.project.web;

import com.teamdaisy.server.common.error.DaisyException;
import com.teamdaisy.server.common.error.ErrorCode;
import com.teamdaisy.server.deployment.application.DeploymentExecutionService.Decision;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;

/**
 * W-01 승인 요청이에요. {@code POST /deployments/{id}/approvals}
 *
 * <p>공개 {@code decision} 은 웹·앱 계약 그대로 {@code approve}·{@code reject} 예요. 저장 상태 {@code
 * approved}·{@code rejected} 와 섞지 않아요.
 *
 * <p>사용자가 본 대상만 승인해요 (S4). 그래서 {@code items} 가 비면 승인 대기 전체로 해석하지 않고 거절해요. 서버가 대상을 채우면 화면에 없던 대상까지
 * 승인될 수 있어요.
 *
 * @param kind 승인 종류. {@code plan} 만 받아요
 * @param decision {@code approve} 또는 {@code reject}
 * @param confirmText 삭제가 있는 plan 의 확인 문구. 맞는지는 실행 서비스가 판정해요
 * @param comment 받지만 저장할 자리가 없어 지금은 쓰지 않아요
 * @param items 사용자가 본 승인 대기 대상과 승인 ID
 */
public record ApprovalRequest(
    String kind, String decision, String confirmText, String comment, List<Item> items) {
  static final String KIND_PLAN = "plan";
  static final String APPROVE = "approve";
  static final String REJECT = "reject";

  public record Item(String targetId, String approvalId) {}

  /**
   * 실행 서비스가 받는 대상별 결정으로 바꿔요.
   *
   * <p>모든 항목에 같은 결정·확인 문구를 넣어요 (계약: 공개 요청의 단일 decision·confirm_text 를 각 항목에 동일하게 전달). 승인 대기 전체와
   * 맞는지, 옛 승인인지는 실행 서비스가 판정해요.
   *
   * <p><b>중복 {@code target_id} 는 Map 으로 바꾸기 전에 거절해요.</b> 그대로 넣으면 앞 항목이 조용히 덮여요.
   */
  public Map<String, Decision> toDecisions() {
    if (!KIND_PLAN.equals(kind)) {
      throw invalid();
    }
    boolean approved = approved(decision);
    if (items == null || items.isEmpty()) {
      throw invalid();
    }
    Set<String> seen = new HashSet<>();
    Map<String, Decision> decisions = new LinkedHashMap<>();
    for (Item item : items) {
      if (item == null || blank(item.targetId()) || blank(item.approvalId())) {
        throw invalid();
      }
      if (!seen.add(item.targetId())) {
        throw invalid();
      }
      decisions.put(item.targetId(), new Decision(item.approvalId(), approved, confirmText));
    }
    return decisions;
  }

  private static boolean approved(String decision) {
    if (APPROVE.equals(decision)) {
      return true;
    }
    if (REJECT.equals(decision)) {
      return false;
    }
    throw invalid();
  }

  private static boolean blank(String value) {
    return value == null || value.isBlank();
  }

  private static DaisyException invalid() {
    return new DaisyException(ErrorCode.VALIDATION_FAILED);
  }
}
