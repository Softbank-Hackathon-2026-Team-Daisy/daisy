package com.teamdaisy.server.project.web;

import static org.assertj.core.api.Assertions.assertThat;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ObjectNode;
import com.teamdaisy.server.project.application.DeploymentDetailReader;
import com.teamdaisy.server.project.application.DeploymentDetailReader.DeploymentDetail;
import com.teamdaisy.server.project.application.DeploymentDetailReader.DeploymentRow;
import com.teamdaisy.server.project.application.DeploymentDetailReader.PendingApproval;
import com.teamdaisy.server.project.application.DeploymentDetailReader.TargetRow;
import java.time.Instant;
import java.util.List;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

/**
 * 배포 상세(A-04)의 값 변환을 고정해요 (server/SPEC.md 「배포 상세 A-04」).
 *
 * <p>승인 화면은 {@code pending_approvals} 의 ID 를 그대로 보내요. 여기가 틀리면 승인이 409 로 막혀요.
 */
class DeploymentDetailResponseTest {
  private static final ObjectMapper MAPPER = new ObjectMapper();
  private static final Instant AT = Instant.parse("2026-10-02T00:00:00Z");

  private static DeploymentRow deployment(String kind, ObjectNode images) {
    return new DeploymentRow(
        "dep_1",
        "prj_1",
        "src_1",
        "a".repeat(40),
        images,
        "awaiting_approval",
        kind,
        // DB 의 ck_dep_lineage 와 같은 조합만 만들어요: rollback 만 원본, retry 만 재시도 원본을 가져요.
        "rollback".equals(kind) ? "dep_0" : null,
        "retry".equals(kind) ? "dep_0" : null,
        "데모 운영자",
        AT,
        null,
        7L);
  }

  private static TargetRow target(String id, int attempt) {
    ObjectNode snapshot =
        MAPPER.createObjectNode().put("environment_type", "aws").put("name", id + "-name");
    return new TargetRow(
        id,
        snapshot,
        "awaiting_approval",
        attempt,
        false,
        null,
        null,
        AT,
        null,
        null,
        null,
        null,
        null,
        null);
  }

  private static ObjectNode image(ObjectNode into, String service) {
    into.set(
        service,
        MAPPER
            .createObjectNode()
            .put("image_ref", "img:" + service)
            .put("digest", "sha256:" + service));
    return into;
  }

  @Test
  @DisplayName("승인 대기는 { target_id, approval_id } 로 그대로 나가요")
  void pendingApprovalsAreCopied() {
    var response =
        DeploymentDetailResponse.of(
            new DeploymentDetail(
                deployment("normal", null),
                List.of(target("tgt_aws", 1)),
                List.of(new PendingApproval("tgt_aws", "apv_7"))));

    assertThat(response.pendingApprovals())
        .containsExactly(new DeploymentDetailResponse.Approval("tgt_aws", "apv_7"));
  }

  @Test
  @DisplayName("kind 는 rollback 만 내보내고 normal·retry 는 null 이에요")
  void kindIsRollbackOrNull() {
    assertThat(response("rollback").kind()).isEqualTo("rollback");
    assertThat(response("rollback").rolledBackFrom()).isEqualTo("dep_0");
    assertThat(response("normal").kind()).isNull();
    assertThat(response("retry").kind()).isNull();
  }

  private static DeploymentDetailResponse response(String kind) {
    return DeploymentDetailResponse.of(
        new DeploymentDetail(deployment(kind, null), List.of(), List.of()));
  }

  @Test
  @DisplayName("시도 0 은 null 이고, 근거 없는 단계·URL·이미지·헬스는 null 이에요")
  void unknownFieldsAreNull() {
    var zero = DeploymentDetailResponse.target(target("tgt_aws", 0));
    var two = DeploymentDetailResponse.target(target("tgt_gcp", 2));

    assertThat(zero.attempt()).isNull();
    assertThat(two.attempt()).isEqualTo(2);
    assertThat(zero.step()).isNull();
    assertThat(zero.stepState()).isNull();
    assertThat(zero.url()).isNull();
    assertThat(zero.imageDigest()).isNull();
    assertThat(zero.healthSummary()).isNull();
    assertThat(zero.type()).isEqualTo("aws");
    assertThat(zero.name()).isEqualTo("tgt_aws-name");
  }

  @Test
  @DisplayName("이미지가 하나면 scalar, 여럿이면 images[], 없으면 전부 null 이에요")
  void imagesFlatten() {
    var single =
        DeploymentDetailResponse.of(
            new DeploymentDetail(
                deployment("normal", image(MAPPER.createObjectNode(), "web")),
                List.of(),
                List.of()));
    assertThat(single.image()).isEqualTo("img:web");
    assertThat(single.imageDigest()).isEqualTo("sha256:web");
    assertThat(single.images()).isNull();

    var multi =
        DeploymentDetailResponse.of(
            new DeploymentDetail(
                deployment("normal", image(image(MAPPER.createObjectNode(), "web"), "api")),
                List.of(),
                List.of()));
    assertThat(multi.image()).isNull();
    assertThat(multi.images()).hasSize(2);

    var none = response("normal");
    assertThat(none.image()).isNull();
    assertThat(none.images()).isNull();
  }

  @Test
  @DisplayName("단계는 가장 최근 단계 이벤트에서 와요: started→running, completed→done, failed→failed")
  void stepFromLatestEvent() {
    ObjectNode snapshot = MAPPER.createObjectNode().put("environment_type", "aws");
    var row =
        new TargetRow(
            "tgt_aws", snapshot, "running", 1, false, null, null, AT, null, "plan", "running", null,
            null, null);
    var target = DeploymentDetailResponse.target(row);

    assertThat(target.step()).isEqualTo("plan");
    assertThat(target.stepState()).isEqualTo("running");
    assertThat(DeploymentDetailReader.stepState("step.started")).isEqualTo("running");
    assertThat(DeploymentDetailReader.stepState("step.completed")).isEqualTo("done");
    assertThat(DeploymentDetailReader.stepState("step.failed")).isEqualTo("failed");
    assertThat(DeploymentDetailReader.stepState("log.batch")).isNull();
  }

  @Test
  @DisplayName("승인 직후 표시: 승인 상태는 그대로, apply 제출 상태는 queued·unknown·rejected 로 묶어요")
  void approvalAndApplyDispatch() {
    ObjectNode snapshot = MAPPER.createObjectNode().put("environment_type", "aws");
    var target =
        DeploymentDetailResponse.target(
            new TargetRow(
                "tgt_aws",
                snapshot,
                "awaiting_approval",
                1,
                false,
                null,
                null,
                AT,
                null,
                null,
                null,
                "approved",
                "queued",
                null));
    assertThat(target.state()).isEqualTo("awaiting_approval");
    assertThat(target.approvalState()).isEqualTo("approved");
    assertThat(target.applyDispatch()).isEqualTo("queued");

    assertThat(DeploymentDetailReader.applyDispatch("apply", "pending")).isEqualTo("queued");
    assertThat(DeploymentDetailReader.applyDispatch("apply", "dispatching")).isEqualTo("queued");
    assertThat(DeploymentDetailReader.applyDispatch("apply", "accepted")).isEqualTo("queued");
    assertThat(DeploymentDetailReader.applyDispatch("apply", "unknown")).isEqualTo("unknown");
    assertThat(DeploymentDetailReader.applyDispatch("apply", "rejected")).isEqualTo("rejected");
    assertThat(DeploymentDetailReader.applyDispatch("prepare", "accepted")).isNull();
    assertThat(DeploymentDetailReader.applyDispatch(null, null)).isNull();
  }

  private static final String DIGEST = "sha256:" + "ab".repeat(32);

  private static ObjectNode result(int services, String digest) {
    ObjectNode result = MAPPER.createObjectNode().put("plan_id", "plan_1");
    ObjectNode urls = result.putObject("public_urls");
    ObjectNode images = result.putObject("image_refs");
    for (int i = 0; i < services; i++) {
      String name = i == 0 ? "hellocalc" : "svc" + i;
      urls.put(name, "https://aws.unibloom.cloud" + (i == 0 ? "" : "/" + i));
      images
          .putObject(name)
          .put("image_ref", "img:" + name)
          .put("digest", digest)
          .put("commit_sha", "c");
    }
    return result;
  }

  private static DeploymentDetailResponse.Target succeeded(ObjectNode result) {
    ObjectNode snapshot = MAPPER.createObjectNode().put("environment_type", "aws");
    return DeploymentDetailResponse.target(
        new TargetRow(
            "tgt_aws",
            snapshot,
            "succeeded",
            1,
            false,
            null,
            null,
            AT,
            AT,
            "health_check",
            "done",
            "approved",
            null,
            result));
  }

  @Test
  @DisplayName("성공 결과의 서비스가 하나면 url·image_digest 는 그 값이고 health_summary 는 null 이에요 (R1)")
  void urlAndDigestFromResult() {
    var target = succeeded(result(1, DIGEST));
    assertThat(target.url()).isEqualTo("https://aws.unibloom.cloud");
    assertThat(target.imageDigest()).isEqualTo(DIGEST);
    assertThat(target.healthSummary()).isNull();
  }

  @Test
  @DisplayName("결과가 없거나 서비스가 여럿이거나 모양이 틀리면 그 필드만 null 이에요 (R2)")
  void resultEdgeCases() {
    assertThat(succeeded(null).url()).isNull();
    assertThat(succeeded(null).imageDigest()).isNull();

    var two = succeeded(result(2, DIGEST));
    assertThat(two.url()).isNull();
    assertThat(two.imageDigest()).isNull();

    var badDigest = succeeded(result(1, "sha256:short"));
    assertThat(badDigest.url()).isEqualTo("https://aws.unibloom.cloud");
    assertThat(badDigest.imageDigest()).isNull();

    ObjectNode notObject = result(1, DIGEST);
    notObject.put("public_urls", "https://aws.unibloom.cloud");
    notObject.putArray("image_refs");
    assertThat(succeeded(notObject).url()).isNull();
    assertThat(succeeded(notObject).imageDigest()).isNull();

    ObjectNode urlNotText = result(1, DIGEST);
    urlNotText.putObject("public_urls").put("hellocalc", 1);
    assertThat(succeeded(urlNotText).url()).isNull();
    assertThat(succeeded(urlNotText).imageDigest()).isEqualTo(DIGEST);
  }
}
