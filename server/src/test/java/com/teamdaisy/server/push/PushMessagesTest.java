package com.teamdaisy.server.push;

import static org.assertj.core.api.Assertions.assertThat;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.teamdaisy.server.push.PushMessages.Kind;
import com.teamdaisy.server.push.PushMessages.Notification;
import com.teamdaisy.server.push.PushMessages.PushEvent;
import java.util.List;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

/** 이벤트 → 알림 묶기·문구 키·payload 모양을 DB 없이 봐요 (ios/SPEC.md §6-5 계약). */
class PushMessagesTest {
  private static final ObjectMapper JSON = new ObjectMapper();

  private static PushEvent event(long id, String deployment, String type, String status) {
    return new PushEvent(id, "prj_1", "sample-monolith", deployment, type, status);
  }

  private static JsonNode payload(Notification notification) throws Exception {
    return JSON.readTree(notification.payloadJson());
  }

  @Test
  @DisplayName("대상 3개의 approval.required 는 알림 하나예요")
  void groupsApprovalPerDeployment() throws Exception {
    var notifications =
        PushMessages.plan(
            List.of(
                event(1, "dep_1", "approval.required", "awaiting_approval"),
                event(2, "dep_1", "approval.required", "awaiting_approval"),
                event(3, "dep_1", "approval.required", "awaiting_approval")));

    assertThat(notifications).hasSize(1);
    Notification only = notifications.getFirst();
    assertThat(only.kind()).isEqualTo(Kind.APPROVAL_REQUIRED);
    assertThat(only.collapseId()).isEqualTo("approval-dep_1");
    JsonNode expected =
        JSON.readTree(
            """
            {"aps":{"alert":{"title-loc-key":"push.approval.title","loc-key":"push.approval.body",
              "loc-args":["sample-monolith"]},"sound":"default","thread-id":"prj_1"},
             "kind":"approval_required","project_id":"prj_1","deployment_id":"dep_1"}
            """);
    assertThat(payload(only)).isEqualTo(expected);
  }

  @Test
  @DisplayName("완료 상태를 kind·문구 키로 바꾸고 취소·모르는 상태는 보내지 않아요")
  void mapsCompletionStates() throws Exception {
    var notifications =
        PushMessages.plan(
            List.of(
                event(1, "dep_s", "deployment.completed", "succeeded"),
                event(2, "dep_p", "deployment.completed", "partially_succeeded"),
                event(3, "dep_f", "deployment.completed", "failed"),
                event(4, "dep_c", "deployment.completed", "cancelled"),
                event(5, "dep_u", "deployment.completed", "something_new"),
                event(6, "dep_n", "deployment.completed", null),
                event(7, "dep_x", "deployment.state_changed", "running")));

    assertThat(notifications)
        .extracting(Notification::deploymentId)
        .containsExactly("dep_s", "dep_p", "dep_f");
    assertThat(notifications)
        .extracting(n -> n.kind().code)
        .containsExactly(
            "deployment_succeeded", "deployment_partially_succeeded", "deployment_failed");
    assertThat(notifications)
        .extracting(Notification::collapseId)
        .containsExactly("result-dep_s", "result-dep_p", "result-dep_f");
    assertThat(payload(notifications.get(0)).at("/aps/alert/title-loc-key").asText())
        .isEqualTo("push.succeeded.title");
    assertThat(payload(notifications.get(1)).at("/aps/alert/loc-key").asText())
        .isEqualTo("push.partial.body");
    assertThat(payload(notifications.get(2)).at("/aps/alert/title-loc-key").asText())
        .isEqualTo("push.failed.title");
  }

  @Test
  @DisplayName("같은 배포의 승인 요청과 완료는 따로 보내요")
  void approvalAndResultAreSeparate() {
    var notifications =
        PushMessages.plan(
            List.of(
                event(1, "dep_1", "approval.required", "awaiting_approval"),
                event(2, "dep_2", "approval.required", "awaiting_approval"),
                event(3, "dep_1", "deployment.completed", "failed")));

    assertThat(notifications)
        .extracting(Notification::collapseId)
        .containsExactly("approval-dep_1", "approval-dep_2", "result-dep_1");
  }
}
