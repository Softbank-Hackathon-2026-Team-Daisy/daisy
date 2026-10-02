package com.teamdaisy.server.project.web;

import com.teamdaisy.server.common.error.DaisyException;
import com.teamdaisy.server.common.error.ErrorCode;
import com.teamdaisy.server.common.web.PageResponse;
import com.teamdaisy.server.identity.auth.AuthPrincipal;
import com.teamdaisy.server.identity.web.CurrentAccount;
import com.teamdaisy.server.project.access.ProjectAccessService;
import com.teamdaisy.server.project.application.AiCostConverter;
import com.teamdaisy.server.project.application.AiUsageReader;
import com.teamdaisy.server.project.application.AiUsageReader.CallRow;
import io.swagger.v3.oas.annotations.security.SecurityRequirement;
import java.time.Instant;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/**
 * AI 호출별 기록이에요 (WR-11). 합계는 A-05 {@code ai_usage} 를 기준으로 봐요.
 *
 * <p>줄마다 원화로 반올림해서, 줄을 더한 값은 A-05 합계(USD 를 먼저 더한 뒤 한 번 반올림)와 조금 다를 수 있어요.
 */
@RestController
@SecurityRequirement(name = "bearerAuth")
public class AiUsageController {
  private final ProjectAccessService access;
  private final AiUsageReader usage;
  private final AiCostConverter cost;

  public AiUsageController(ProjectAccessService access, AiUsageReader usage, AiCostConverter cost) {
    this.access = access;
    this.usage = usage;
    this.cost = cost;
  }

  /**
   * 호출 한 번이에요. 확인하지 못한 값은 0 이 아니라 null 이에요.
   *
   * @param status LLM 호출 결과 succeeded·failed·unknown 이에요. Terraform 검증 결과가 아니에요
   * @param note 원본 설명이 없어 지금은 null 이에요
   */
  public record AiUsageCall(
      Instant at,
      String deploymentId,
      String targetId,
      String step,
      int attempt,
      Long tokens,
      Long costKrw,
      String status,
      String note) {

    static AiUsageCall of(CallRow row, AiCostConverter cost) {
      return new AiUsageCall(
          row.at(),
          row.deploymentId(),
          row.targetId(),
          row.step(),
          row.attempt(),
          row.tokens(),
          cost.toKrw(row.costUsd()),
          row.status(),
          null);
    }
  }

  @GetMapping("/projects/{projectId}/ai-usage")
  public PageResponse<AiUsageCall> calls(
      @CurrentAccount AuthPrincipal principal,
      @PathVariable String projectId,
      @RequestParam(name = "deployment_id", required = false) String deploymentId) {
    access.requireRead(principal, projectId);
    if (deploymentId == null || deploymentId.isBlank()) {
      throw new DaisyException(ErrorCode.VALIDATION_FAILED);
    }
    if (!usage.hasDeployment(projectId, deploymentId)) {
      throw new DaisyException(ErrorCode.NOT_FOUND);
    }
    return new PageResponse<>(
        usage.calls(projectId, deploymentId).stream()
            .map(row -> AiUsageCall.of(row, cost))
            .toList(),
        null);
  }
}
