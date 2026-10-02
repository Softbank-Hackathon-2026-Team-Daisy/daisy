package com.teamdaisy.server.project.web;

import static org.assertj.core.api.Assertions.assertThat;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ObjectNode;
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
        "dep_0",
        null,
        "데모 운영자",
        AT,
        null,
        7L);
  }

  private static TargetRow target(String id, int attempt) {
    ObjectNode snapshot =
        MAPPER.createObjectNode().put("environment_type", "aws").put("name", id + "-name");
    return new TargetRow(id, snapshot, "awaiting_approval", attempt, false, null, null, AT, null);
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
}
