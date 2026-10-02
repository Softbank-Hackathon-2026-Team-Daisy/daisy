package com.teamdaisy.server.project.web;

import com.teamdaisy.server.deployment.application.DeploymentQueryService;
import com.teamdaisy.server.identity.auth.AuthPrincipal;
import com.teamdaisy.server.identity.web.CurrentAccount;
import com.teamdaisy.server.project.application.DeploymentDetailReader;
import io.swagger.v3.oas.annotations.security.SecurityRequirement;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RestController;

/**
 * 배포 조회 API 예요. 지금은 상세(A-04)만 있고, 목록(A-03)·plan(A-05)·로그(A-07)가 여기 더해져요.
 *
 * <p>권한은 승환의 {@code projectIdOf} 로 확인해요. 없는 배포와 접근할 수 없는 배포는 404 예요.
 */
@RestController
@SecurityRequirement(name = "bearerAuth")
public class DeploymentQueryController {
  private final DeploymentQueryService queries;
  private final DeploymentDetailReader details;

  public DeploymentQueryController(DeploymentQueryService queries, DeploymentDetailReader details) {
    this.queries = queries;
    this.details = details;
  }

  /** 배포 한 건의 스냅샷이에요 (A-04). 승인할 때 보낼 {@code approval_id} 는 {@code pending_approvals} 에 있어요. */
  @GetMapping("/deployments/{deploymentId}")
  public DeploymentDetailResponse detail(
      @CurrentAccount AuthPrincipal principal, @PathVariable String deploymentId) {
    String projectId = queries.projectIdOf(principal.accountId(), deploymentId);
    return DeploymentDetailResponse.of(details.read(projectId, deploymentId));
  }
}
