package com.teamdaisy.server.push;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ObjectNode;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * 배포 이벤트 묶음을 보낼 알림으로 바꿔요. DB·네트워크 없이 테스트할 수 있게 계산만 해요.
 *
 * <p>문구는 앱이 String Catalog 로 현지화해요. 그래서 {@code loc-key} 와 {@code loc-args[0]=프로젝트 이름} 만 보내요.
 */
final class PushMessages {
  static final String APPROVAL_REQUIRED = "approval.required";
  static final String DEPLOYMENT_COMPLETED = "deployment.completed";
  private static final ObjectMapper JSON = new ObjectMapper();

  /** 앱이 받는 {@code kind} 와 문구 키예요. */
  enum Kind {
    APPROVAL_REQUIRED("approval_required", "push.approval", "approval-"),
    DEPLOYMENT_SUCCEEDED("deployment_succeeded", "push.succeeded", "result-"),
    DEPLOYMENT_PARTIALLY_SUCCEEDED("deployment_partially_succeeded", "push.partial", "result-"),
    DEPLOYMENT_FAILED("deployment_failed", "push.failed", "result-");

    final String code;
    final String locPrefix;
    final String collapsePrefix;

    Kind(String code, String locPrefix, String collapsePrefix) {
      this.code = code;
      this.locPrefix = locPrefix;
      this.collapsePrefix = collapsePrefix;
    }

    /** 배포 최종 상태에서 kind 를 골라요. 취소·알 수 없는 값은 보내지 않아요(null). */
    static Kind ofCompletion(String status) {
      if (status == null) return null;
      return switch (status) {
        case "succeeded" -> DEPLOYMENT_SUCCEEDED;
        case "partially_succeeded" -> DEPLOYMENT_PARTIALLY_SUCCEEDED;
        case "failed" -> DEPLOYMENT_FAILED;
        default -> null;
      };
    }
  }

  /**
   * 발송 후보 이벤트 하나예요.
   *
   * @param status {@code deployment.completed} 의 payload {@code status}(배포 최종 상태)
   */
  record PushEvent(
      long id,
      String projectId,
      String projectName,
      String deploymentId,
      String eventType,
      String status) {}

  record Notification(
      Kind kind, String projectId, String deploymentId, String collapseId, String payloadJson) {}

  private PushMessages() {}

  /**
   * 이벤트를 알림으로 묶어요.
   *
   * <p>{@code approval.required} 는 대상마다 하나씩 생겨서 배포 하나에 알림 하나로 줄여요. 같은 배포의 완료가 여러 번이면 마지막 상태를 보내요.
   * 순서는 각 묶음의 첫 이벤트 순서예요.
   */
  static List<Notification> plan(List<PushEvent> events) {
    Map<String, Notification> grouped = new LinkedHashMap<>();
    for (PushEvent event : events) {
      if (event.deploymentId() == null) continue;
      if (APPROVAL_REQUIRED.equals(event.eventType())) {
        grouped.computeIfAbsent(
            "approval:" + event.deploymentId(), key -> notification(Kind.APPROVAL_REQUIRED, event));
      } else if (DEPLOYMENT_COMPLETED.equals(event.eventType())) {
        Kind kind = Kind.ofCompletion(event.status());
        if (kind != null) grouped.put("result:" + event.deploymentId(), notification(kind, event));
      }
    }
    return new ArrayList<>(grouped.values());
  }

  static Notification notification(Kind kind, PushEvent event) {
    ObjectNode root = JSON.createObjectNode();
    ObjectNode aps = root.putObject("aps");
    ObjectNode alert = aps.putObject("alert");
    alert.put("title-loc-key", kind.locPrefix + ".title");
    alert.put("loc-key", kind.locPrefix + ".body");
    alert.putArray("loc-args").add(event.projectName() == null ? "" : event.projectName());
    aps.put("sound", "default");
    aps.put("thread-id", event.projectId());
    root.put("kind", kind.code);
    root.put("project_id", event.projectId());
    root.put("deployment_id", event.deploymentId());
    try {
      return new Notification(
          kind,
          event.projectId(),
          event.deploymentId(),
          kind.collapsePrefix + event.deploymentId(),
          JSON.writeValueAsString(root));
    } catch (JsonProcessingException e) {
      throw new IllegalStateException("push_payload_failed");
    }
  }
}
