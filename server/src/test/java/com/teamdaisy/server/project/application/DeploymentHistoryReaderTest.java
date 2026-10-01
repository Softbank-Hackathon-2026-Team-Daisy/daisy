package com.teamdaisy.server.project.application;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.argThat;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.fasterxml.jackson.databind.node.JsonNodeFactory;
import com.teamdaisy.server.common.error.DaisyException;
import com.teamdaisy.server.common.error.ErrorCode;
import com.teamdaisy.server.deployment.application.DeploymentQueryService;
import com.teamdaisy.server.deployment.application.DeploymentQueryService.CurrentDeployment;
import com.teamdaisy.server.deployment.application.DeploymentQueryService.ServiceImage;
import com.teamdaisy.server.deployment.application.ExecutionAccess;
import com.teamdaisy.server.project.application.DeploymentHistoryReader.CurrentView;
import com.teamdaisy.server.project.domain.Target;
import com.teamdaisy.server.project.web.TargetStatusResponse;
import java.time.Instant;
import java.util.List;
import java.util.Map;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.test.util.ReflectionTestUtils;

/**
 * A-02 {@code current} 가 대상 하나 때문에 통째로 깨지지 않는지 고정해요 (server/SPEC.md ⑤ · 검증 V11).
 *
 * <p>트랜잭션과 엮인 실패(롤백 전용)는 단위 테스트로 잡히지 않아요. 그건 실제 DB 기동으로 따로 확인해요.
 */
class DeploymentHistoryReaderTest {
  private static final String PROJECT = "prj_1";
  private static final String ACTOR = "acc_1";
  private static final Instant AT = Instant.parse("2026-10-02T00:00:00Z");

  private final DeploymentQueryService queries = mock(DeploymentQueryService.class);
  private final ExecutionAccess access = mock(ExecutionAccess.class);
  private final DeploymentHistoryReader reader = new DeploymentHistoryReader(queries, access);

  private static Target target(String id, String pointer) {
    Target target =
        Target.create(
            id,
            PROJECT,
            id,
            "aws",
            "s/" + id,
            JsonNodeFactory.instance.objectNode(),
            "unknown",
            AT);
    ReflectionTestUtils.setField(target, "currentDeploymentTargetId", pointer);
    return target;
  }

  private static CurrentDeployment deployment(String id, List<ServiceImage> images) {
    return new CurrentDeployment(id, "src_1", "a".repeat(40), images, AT);
  }

  @Test
  @DisplayName("포인터가 하나도 없으면 조회 서비스를 부르지 않고 전부 none 이에요")
  void noPointerNoCall() {
    Map<String, CurrentView> views =
        reader.current(ACTOR, PROJECT, List.of(target("tgt_a", null), target("tgt_b", null)));

    assertThat(views.values()).allMatch(view -> view.status().equals("none"));
    verify(queries, never()).current(any(), any(), any());
  }

  @Test
  @DisplayName("일괄 호출이 성공하면 포인터 있는 대상은 confirmed, 없는 대상은 none 이에요")
  void batchSuccess() {
    when(queries.current(eq(ACTOR), eq(PROJECT), any()))
        .thenReturn(Map.of("tgt_a", deployment("dep_1", null)));

    Map<String, CurrentView> views =
        reader.current(ACTOR, PROJECT, List.of(target("tgt_a", "dt_1"), target("tgt_b", null)));

    assertThat(views.get("tgt_a").status()).isEqualTo("confirmed");
    assertThat(views.get("tgt_a").deployment().deploymentId()).isEqualTo("dep_1");
    assertThat(views.get("tgt_b").status()).isEqualTo("none");
  }

  @Test
  @DisplayName("일괄 호출이 409 면 대상별로 다시 불러 문제 대상만 unverified 예요")
  void batchConflictIsIsolated() {
    when(queries.current(eq(ACTOR), eq(PROJECT), argThat(pointers -> pointers.size() == 2)))
        .thenThrow(new DaisyException(ErrorCode.STATE_CONFLICT));
    when(queries.current(
            eq(ACTOR),
            eq(PROJECT),
            argThat(p -> p.size() == 1 && p.get(0).targetId().equals("tgt_a"))))
        .thenReturn(Map.of("tgt_a", deployment("dep_1", null)));
    when(queries.current(
            eq(ACTOR),
            eq(PROJECT),
            argThat(p -> p.size() == 1 && p.get(0).targetId().equals("tgt_b"))))
        .thenThrow(new DaisyException(ErrorCode.STATE_CONFLICT));

    Map<String, CurrentView> views =
        reader.current(ACTOR, PROJECT, List.of(target("tgt_a", "dt_1"), target("tgt_b", "dt_2")));

    assertThat(views.get("tgt_a").status()).isEqualTo("confirmed");
    assertThat(views.get("tgt_b").status()).isEqualTo("unverified");
    assertThat(views.get("tgt_b").deployment()).isNull();
  }

  @Test
  @DisplayName("일괄 404 뒤 권한 재확인이 실패하면 unverified 로 숨기지 않고 404 를 그대로 올려요 (#42 리뷰)")
  void revokedMembershipPropagates() {
    when(queries.current(any(), any(), any())).thenThrow(new DaisyException(ErrorCode.NOT_FOUND));
    org.mockito.Mockito.doThrow(new DaisyException(ErrorCode.NOT_FOUND))
        .when(access)
        .requireRead(ACTOR, PROJECT);

    assertThatThrownBy(() -> reader.current(ACTOR, PROJECT, List.of(target("tgt_a", "dt_1"))))
        .isInstanceOf(DaisyException.class)
        .extracting(e -> ((DaisyException) e).errorCode())
        .isEqualTo(ErrorCode.NOT_FOUND);
    // 일괄 한 번만 부르고, 대상별로 다시 부르지 않아요.
    verify(queries, org.mockito.Mockito.times(1)).current(any(), any(), any());
  }

  @Test
  @DisplayName("권한 오류(403)는 대상 문제가 아니라서 격리하지 않고 그대로 올려요")
  void forbiddenPropagates() {
    when(queries.current(any(), any(), any())).thenThrow(new DaisyException(ErrorCode.FORBIDDEN));

    assertThatThrownBy(() -> reader.current(ACTOR, PROJECT, List.of(target("tgt_a", "dt_1"))))
        .isInstanceOf(DaisyException.class)
        .extracting(e -> ((DaisyException) e).errorCode())
        .isEqualTo(ErrorCode.FORBIDDEN);
  }

  @Test
  @DisplayName("이미지가 하나면 image·image_digest, 여럿이면 둘 다 null 이고 images 예요")
  void imageFlattening() {
    var single =
        TargetStatusResponse.of(
            target("tgt_a", "dt_1"),
            new CurrentView(
                "confirmed",
                deployment("dep_1", List.of(new ServiceImage("web", "img:1", "sha256:x")))));
    assertThat(single.current().image()).isEqualTo("img:1");
    assertThat(single.current().imageDigest()).isEqualTo("sha256:x");
    assertThat(single.current().images()).isNull();
    assertThat(single.currentStatus()).isEqualTo("confirmed");

    var multi =
        TargetStatusResponse.of(
            target("tgt_a", "dt_1"),
            new CurrentView(
                "confirmed",
                deployment(
                    "dep_1",
                    List.of(
                        new ServiceImage("api", "img:a", null),
                        new ServiceImage("web", "img:w", null)))));
    assertThat(multi.current().image()).isNull();
    assertThat(multi.current().imageDigest()).isNull();
    assertThat(multi.current().images()).hasSize(2);
  }

  @Test
  @DisplayName("빌드 페이지가 비면 조회 서비스를 부르지 않아요")
  void emptyBuildPage() {
    assertThat(reader.deployedTo(ACTOR, PROJECT, List.of())).isEmpty();
    verify(queries, never()).deployedTo(any(), any(), any());
  }
}
