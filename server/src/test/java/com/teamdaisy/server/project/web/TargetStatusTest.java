package com.teamdaisy.server.project.web;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.fasterxml.jackson.databind.node.JsonNodeFactory;
import com.teamdaisy.server.common.error.DaisyException;
import com.teamdaisy.server.common.error.ErrorCode;
import com.teamdaisy.server.common.web.PageResponse;
import com.teamdaisy.server.deployment.application.DeploymentQueryService;
import com.teamdaisy.server.identity.auth.AuthPrincipal;
import com.teamdaisy.server.project.access.ProjectAccess;
import com.teamdaisy.server.project.access.ProjectAccessService;
import com.teamdaisy.server.project.application.DeploymentHistoryReader;
import com.teamdaisy.server.project.domain.ProjectRepository;
import com.teamdaisy.server.project.domain.SourceVersionRepository;
import com.teamdaisy.server.project.domain.Target;
import com.teamdaisy.server.project.domain.TargetRepository;
import java.time.Instant;
import java.util.List;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

/**
 * 환경별 현재 상태 조회(A-02)를 고정해요.
 *
 * <p>핵심은 둘이에요. 접근 판정이 질의보다 먼저 돌아야 하고, 근거가 없는 필드를 값으로 채우지 않아야 해요.
 */
class TargetStatusTest {
  private static final String PROJECT = "prj_1";
  private static final AuthPrincipal OWNER = new AuthPrincipal("acc_1", "daisy", "owner");

  private final ProjectRepository projects = mock(ProjectRepository.class);
  private final TargetRepository targets = mock(TargetRepository.class);
  private final SourceVersionRepository versions = mock(SourceVersionRepository.class);
  private final ProjectAccessService access = mock(ProjectAccessService.class);
  private final DeploymentQueryService queries = mock(DeploymentQueryService.class);
  private final ProjectController controller =
      new ProjectController(
          projects, targets, versions, access, new DeploymentHistoryReader(queries));

  private static Target target(String id, String name, String type, String connectionState) {
    return Target.create(
        id,
        PROJECT,
        name,
        type,
        PROJECT + "/" + id,
        JsonNodeFactory.instance.objectNode(),
        connectionState,
        Instant.parse("2026-10-01T00:00:00Z"));
  }

  @Test
  @DisplayName("접근 판정이 대상 질의보다 먼저 돌아요")
  void accessIsCheckedBeforeQuery() {
    when(access.requireRead(any(), any())).thenThrow(new DaisyException(ErrorCode.NOT_FOUND));

    assertThatThrownBy(() -> controller.targetStatus(OWNER, PROJECT))
        .isInstanceOf(DaisyException.class)
        .extracting(exception -> ((DaisyException) exception).errorCode())
        .isEqualTo(ErrorCode.NOT_FOUND);

    // 판정이 막았으면 질의가 아예 돌지 않아야 해요. 돌면 존재 여부가 응답 시간으로 샐 수 있어요.
    verify(targets, never()).findActiveByProject(any());
  }

  @Test
  @DisplayName("대상이 없으면 오류가 아니라 빈 목록이에요")
  void emptyProjectReturnsEmptyItems() {
    when(access.requireRead(OWNER, PROJECT)).thenReturn(new ProjectAccess(OWNER, PROJECT, true));
    when(targets.findActiveByProject(PROJECT)).thenReturn(List.of());

    PageResponse<TargetStatusResponse> response = controller.targetStatus(OWNER, PROJECT);

    assertThat(response.items()).isEmpty();
    assertThat(response.nextCursor()).isNull();
  }

  @Test
  @DisplayName("근거가 없는 필드를 값으로 채우지 않아요")
  void unknownFieldsStayNull() {
    when(access.requireRead(OWNER, PROJECT)).thenReturn(new ProjectAccess(OWNER, PROJECT, true));
    when(targets.findActiveByProject(PROJECT))
        .thenReturn(List.of(target("tgt_1", "home-lab", "onprem", "unknown")));

    TargetStatusResponse item = controller.targetStatus(OWNER, PROJECT).items().get(0);

    assertThat(item.targetId()).isEqualTo("tgt_1");
    assertThat(item.type()).isEqualTo("onprem");
    assertThat(item.name()).isEqualTo("home-lab");
    assertThat(item.connectionState()).isEqualTo("unknown");
    // 배포가 없으면 current 는 통째로 null 이에요. 빈 객체로 바꾸면 "배포가 있는데 값이 비었다" 로 읽혀요.
    assertThat(item.current()).isNull();
    // 인프라 산출물이 없는 값은 null, health 는 모른다는 뜻의 unknown 이에요.
    assertThat(item.url()).isNull();
    assertThat(item.health()).isEqualTo("unknown");
    assertThat(item.healthSummary()).isNull();
    assertThat(item.imageDigest()).isNull();
    assertThat(item.checkedAt()).isNull();
  }

  @Test
  @DisplayName("읽기 전용 계정도 조회할 수 있어요")
  void viewerCanRead() {
    AuthPrincipal viewer = new AuthPrincipal("acc_2", "judge", AuthPrincipal.VIEWER);
    when(access.requireRead(viewer, PROJECT)).thenReturn(new ProjectAccess(viewer, PROJECT, false));
    when(targets.findActiveByProject(PROJECT))
        .thenReturn(List.of(target("tgt_1", "home-lab", "onprem", "connected")));

    assertThat(controller.targetStatus(viewer, PROJECT).items()).hasSize(1);
  }
}
