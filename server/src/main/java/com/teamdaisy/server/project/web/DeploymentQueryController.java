package com.teamdaisy.server.project.web;

import com.teamdaisy.server.common.error.DaisyException;
import com.teamdaisy.server.common.error.ErrorCode;
import com.teamdaisy.server.common.web.PageResponse;
import com.teamdaisy.server.deployment.application.DeploymentQueryService;
import com.teamdaisy.server.deployment.domain.DeploymentStatus;
import com.teamdaisy.server.identity.auth.AuthPrincipal;
import com.teamdaisy.server.identity.web.CurrentAccount;
import com.teamdaisy.server.project.access.ProjectAccessService;
import com.teamdaisy.server.project.application.DeploymentDetailReader;
import com.teamdaisy.server.project.application.DeploymentDetailReader.DeploymentDetail;
import io.swagger.v3.oas.annotations.security.SecurityRequirement;
import java.util.Arrays;
import java.util.List;
import java.util.Set;
import java.util.stream.Collectors;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/**
 * 배포 조회 API 예요. 지금은 상세(A-04)만 있고, 목록(A-03)·plan(A-05)·로그(A-07)가 여기 더해져요.
 *
 * <p>권한은 승환의 {@code projectIdOf} 로 확인해요. 없는 배포와 접근할 수 없는 배포는 404 예요.
 */
@RestController
@SecurityRequirement(name = "bearerAuth")
public class DeploymentQueryController {
  private static final int DEFAULT_LIMIT = 20;
  private static final Set<String> STATES =
      Arrays.stream(DeploymentStatus.values())
          .map(DeploymentStatus::code)
          .collect(Collectors.toUnmodifiableSet());

  private final DeploymentQueryService queries;
  private final DeploymentDetailReader details;
  private final ProjectAccessService access;

  public DeploymentQueryController(
      DeploymentQueryService queries, DeploymentDetailReader details, ProjectAccessService access) {
    this.queries = queries;
    this.details = details;
    this.access = access;
  }

  /** 배포 한 건의 스냅샷이에요 (A-04). 승인할 때 보낼 {@code approval_id} 는 {@code pending_approvals} 에 있어요. */
  @GetMapping("/deployments/{deploymentId}")
  public DeploymentDetailResponse detail(
      @CurrentAccount AuthPrincipal principal, @PathVariable String deploymentId) {
    String projectId = queries.projectIdOf(principal.accountId(), deploymentId);
    return DeploymentDetailResponse.of(details.read(projectId, deploymentId));
  }

  /**
   * 배포 목록이에요 (A-03). 최신순이고, 승인 대기는 {@code state=awaiting_approval} 로 걸러요 (9/29 결정).
   *
   * <p>한 줄은 A-04 상세와 같은 모양이에요. 커서는 A-06 과 같은 (시각, ID) 불투명 문자열이에요.
   */
  @GetMapping("/projects/{projectId}/deployments")
  public PageResponse<DeploymentDetailResponse> list(
      @CurrentAccount AuthPrincipal principal,
      @PathVariable String projectId,
      @RequestParam(required = false) String state,
      @RequestParam(required = false) String cursor,
      @RequestParam(required = false, defaultValue = "" + DEFAULT_LIMIT) int limit) {
    access.requireRead(principal, projectId);
    if (state != null && !STATES.contains(state)) {
      throw new DaisyException(ErrorCode.VALIDATION_FAILED);
    }
    int size = ProjectController.normalizeLimit(limit);
    BuildCursor after = cursor == null ? null : BuildCursor.decode(cursor);
    // 다음 페이지가 있는지 알려면 한 건 더 받아 봐요. 따로 count 질의를 돌리지 않아요.
    List<DeploymentDetail> rows =
        details.list(
            projectId,
            state,
            after == null ? null : after.receivedAt(),
            after == null ? null : after.id(),
            size + 1);
    boolean hasMore = rows.size() > size;
    List<DeploymentDetail> page = hasMore ? rows.subList(0, size) : rows;
    String nextCursor = null;
    if (hasMore) {
      var last = page.get(page.size() - 1).deployment();
      nextCursor = new BuildCursor(last.createdAt(), last.id()).encode();
    }
    return new PageResponse<>(page.stream().map(DeploymentDetailResponse::of).toList(), nextCursor);
  }
}
