package com.teamdaisy.server.project.web;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import com.teamdaisy.server.common.error.DaisyException;
import com.teamdaisy.server.common.error.ErrorCode;
import com.teamdaisy.server.deployment.application.DeploymentExecutionService.Decision;
import com.teamdaisy.server.project.web.ApprovalRequest.Item;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import java.util.Map;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

/** 공개 승인 요청을 실행 서비스의 대상별 결정으로 바꾸는 규칙을 고정해요 (server/SPEC.md ④). */
class ApprovalRequestTest {
  private static final List<Item> TWO =
      List.of(new Item("tgt_aws", "apv_1"), new Item("tgt_gcp", "apv_2"));

  private static ApprovalRequest request(String kind, String decision, List<Item> items) {
    return new ApprovalRequest(kind, decision, "sample-monolith", null, items);
  }

  private static void assertInvalid(ApprovalRequest request) {
    assertThatThrownBy(request::toDecisions)
        .isInstanceOf(DaisyException.class)
        .extracting(exception -> ((DaisyException) exception).errorCode())
        .isEqualTo(ErrorCode.VALIDATION_FAILED);
  }

  @Test
  @DisplayName("approve 는 모든 항목에 같은 승인·확인 문구로 펼쳐져요")
  void approveSpreadsToEveryItem() {
    Map<String, Decision> decisions = request("plan", "approve", TWO).toDecisions();

    assertThat(decisions)
        .containsExactly(
            Map.entry("tgt_aws", new Decision("apv_1", true, "sample-monolith")),
            Map.entry("tgt_gcp", new Decision("apv_2", true, "sample-monolith")));
  }

  @Test
  @DisplayName("reject 는 approved=false 예요")
  void rejectIsFalse() {
    assertThat(request("plan", "reject", TWO).toDecisions().values())
        .allMatch(decision -> !decision.approved());
  }

  @Test
  @DisplayName("저장 상태 이름(approved·rejected)이나 다른 값은 400 이에요")
  void storedStateNamesAreRejected() {
    assertInvalid(request("plan", "approved", TWO));
    assertInvalid(request("plan", "rejected", TWO));
    assertInvalid(request("plan", "APPROVE", TWO));
    assertInvalid(request("plan", null, TWO));
  }

  @Test
  @DisplayName("kind 는 plan 만 받아요")
  void onlyPlanKind() {
    assertInvalid(request("deploy", "approve", TWO));
    assertInvalid(request(null, "approve", TWO));
  }

  @Test
  @DisplayName("items 가 비면 승인 대기 전체로 보지 않고 400 이에요")
  void emptyItemsAreRejected() {
    assertInvalid(request("plan", "approve", List.of()));
    assertInvalid(request("plan", "approve", null));
  }

  @Test
  @DisplayName("같은 target_id 가 두 번 오면 Map 으로 덮기 전에 400 이에요")
  void duplicateTargetIsRejected() {
    assertInvalid(
        request(
            "plan",
            "approve",
            List.of(new Item("tgt_aws", "apv_1"), new Item("tgt_aws", "apv_9"))));
  }

  @Test
  @DisplayName("빈 target_id·approval_id·null 항목은 400 이에요")
  void incompleteItemsAreRejected() {
    assertInvalid(request("plan", "approve", List.of(new Item("tgt_aws", " "))));
    assertInvalid(request("plan", "approve", List.of(new Item(null, "apv_1"))));
    List<Item> withNull = new ArrayList<>(Arrays.asList(new Item("tgt_aws", "apv_1"), null));
    assertInvalid(request("plan", "approve", withNull));
  }
}
