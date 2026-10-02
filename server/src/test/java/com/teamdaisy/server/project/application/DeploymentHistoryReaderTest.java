package com.teamdaisy.server.project.application;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
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
import com.teamdaisy.server.deployment.application.DeploymentQueryService.CurrentResult;
import com.teamdaisy.server.deployment.application.DeploymentQueryService.ServiceImage;
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
 * A-02 {@code current} 를 승환의 {@code currentByTarget} 결과로 채우는지 고정해요 (server/SPEC.md ⑤ · #42
 * 044a436).
 *
 * <p>대상별 실패를 감싸는 일은 조회 서비스가 해요. 여기서는 결과를 그대로 옮기고, 권한 오류를 숨기지 않는지만 봐요.
 */
class DeploymentHistoryReaderTest {
  private static final String PROJECT = "prj_1";
  private static final String ACTOR = "acc_1";
  private static final Instant AT = Instant.parse("2026-10-02T00:00:00Z");

  private final DeploymentQueryService queries = mock(DeploymentQueryService.class);
  private final DeploymentDetailReader details = mock(DeploymentDetailReader.class);
  private final DeploymentHistoryReader reader = new DeploymentHistoryReader(queries, details);

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
    verify(queries, never()).currentByTarget(any(), any(), any());
  }

  @Test
  @DisplayName("조회 서비스의 대상별 결과(confirmed·unverified·none)를 그대로 옮겨요")
  void resultsAreCopied() {
    when(details.read(PROJECT, "dep_1"))
        .thenReturn(new DeploymentDetailReader.DeploymentDetail(null, List.of(), List.of()));
    when(queries.currentByTarget(eq(ACTOR), eq(PROJECT), any()))
        .thenReturn(
            Map.of(
                "tgt_a", new CurrentResult("confirmed", deployment("dep_1", null)),
                "tgt_b", new CurrentResult("unverified", null),
                "tgt_c", new CurrentResult("none", null)));

    Map<String, CurrentView> views =
        reader.current(
            ACTOR,
            PROJECT,
            List.of(target("tgt_a", "dt_1"), target("tgt_b", "dt_2"), target("tgt_c", null)));

    assertThat(views.get("tgt_a").status()).isEqualTo("confirmed");
    assertThat(views.get("tgt_a").deployment().deploymentId()).isEqualTo("dep_1");
    assertThat(views.get("tgt_b").status()).isEqualTo("unverified");
    assertThat(views.get("tgt_b").deployment()).isNull();
    assertThat(views.get("tgt_c").status()).isEqualTo("none");
  }

  @Test
  @DisplayName("권한 오류(404)는 대상 결과로 숨기지 않고 그대로 올려요 (#42 리뷰)")
  void accessErrorPropagates() {
    when(queries.currentByTarget(any(), any(), any()))
        .thenThrow(new DaisyException(ErrorCode.NOT_FOUND));

    assertThatThrownBy(() -> reader.current(ACTOR, PROJECT, List.of(target("tgt_a", "dt_1"))))
        .isInstanceOf(DaisyException.class)
        .extracting(e -> ((DaisyException) e).errorCode())
        .isEqualTo(ErrorCode.NOT_FOUND);
  }

  @Test
  @DisplayName("이미지가 하나면 image·image_digest, 여럿이면 둘 다 null 이고 images 예요")
  void imageFlattening() {
    var single =
        TargetStatusResponse.of(
            target("tgt_a", "dt_1"),
            new CurrentView(
                "confirmed",
                deployment("dep_1", List.of(new ServiceImage("web", "img:1", "sha256:x"))),
                null));
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
                        new ServiceImage("web", "img:w", null))),
                null));
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
