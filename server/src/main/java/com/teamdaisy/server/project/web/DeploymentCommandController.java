package com.teamdaisy.server.project.web;

import com.teamdaisy.server.deployment.application.DeploymentExecutionService;
import com.teamdaisy.server.deployment.application.DeploymentExecutionService.ControlRequest;
import com.teamdaisy.server.deployment.application.DeploymentExecutionService.DecisionRequest;
import com.teamdaisy.server.deployment.application.DeploymentExecutionService.RollbackRequest;
import com.teamdaisy.server.deployment.application.DeploymentQueryService;
import com.teamdaisy.server.history.application.EventSseService;
import com.teamdaisy.server.identity.auth.AuthPrincipal;
import com.teamdaisy.server.identity.web.CurrentAccount;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.Parameter;
import io.swagger.v3.oas.annotations.media.Content;
import io.swagger.v3.oas.annotations.media.Schema;
import io.swagger.v3.oas.annotations.responses.ApiResponse;
import io.swagger.v3.oas.annotations.security.SecurityRequirement;
import jakarta.servlet.http.HttpServletResponse;
import java.util.List;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.servlet.mvc.method.annotation.SseEmitter;

/**
 * 배포 ID 경로의 명령·이벤트 API 예요. 승인(W-01)·취소(WR-08)·재시도·롤백(WR-14)·배포 SSE(E-01).
 *
 * <p>경로에 배포 ID 만 있어서, 승환의 {@code projectIdOf} 로 프로젝트를 찾아요. 없거나 접근할 수 없는 배포는 404 예요. 조회 권한만 보는 메서드라
 * 변경 권한(viewer 403)은 실행 서비스의 {@code requireWrite} 가 봐요.
 *
 * <p><b>상태를 직접 바꾸지 않아요.</b> 검증한 요청을 실행 서비스로 넘기기만 해요. 지금 상태에서 허용되는지, 옛 승인인지, apply 뒤 취소를 어떻게 다룰지는 실행
 * 서비스가 판정해요 (server/docs/eh/roles.md §3). 트랜잭션도 실행 서비스가 열어요.
 */
@RestController
@RequestMapping("/deployments/{deploymentId}")
@SecurityRequirement(name = "bearerAuth")
public class DeploymentCommandController {
  private final DeploymentExecutionService deployments;
  private final DeploymentQueryService queries;
  private final EventSseService events;

  public DeploymentCommandController(
      DeploymentExecutionService deployments,
      DeploymentQueryService queries,
      EventSseService events) {
    this.deployments = deployments;
    this.queries = queries;
    this.events = events;
  }

  /** 취소·재시도 요청이에요. 고를 대상을 적어요. */
  public record TargetSelection(
      @Schema(requiredMode = Schema.RequiredMode.REQUIRED, description = "대상 ID 목록. 1~50개, 중복 불가")
          List<String> targetIds) {}

  /**
   * 롤백 요청이에요.
   *
   * @param reason 필수, 1000자 이하, 비밀값 제외. 웹은 자동으로 채워요
   * @param triggerDeploymentId 롤백하게 만든 배포 (선택)
   */
  public record RollbackSelection(
      @Schema(
              requiredMode = Schema.RequiredMode.REQUIRED,
              description = "원본 성공 배포에서 되돌릴 대상 ID 목록. 1~50개")
          List<String> targetIds,
      @Schema(
              requiredMode = Schema.RequiredMode.REQUIRED,
              minLength = 1,
              maxLength = 1000,
              description = "롤백 사유. 비밀값 제외")
          String reason,
      @Schema(nullable = true, description = "롤백을 유발한 배포 ID, 선택") String triggerDeploymentId) {}

  /** 승인·거절이에요 (W-01). 승인 대기 대상 전체를 한 번에 보내요. */
  @PostMapping("/approvals")
  @Operation(
      summary = "plan 승인·거절",
      description =
          "A-04 pending_approvals와 같은 items를 보내요. 삭제 포함 plan 승인은 프로젝트 이름 confirm_text가 필요해요. 이전/만료 승인 또는 상태 변경은 409예요.")
  @ApiResponse(
      responseCode = "202",
      description = "결정을 접수했어요. 승인 시 apply 명령이 생기지만 완료를 뜻하지 않아요",
      useReturnTypeSchema = true)
  public ResponseEntity<DeploymentAccepted> decide(
      @CurrentAccount AuthPrincipal principal,
      @PathVariable String deploymentId,
      @Parameter(required = true, description = "멱등 키. 1~255자")
          @RequestHeader(value = DeploymentAccepted.IDEMPOTENCY_KEY, required = false)
          String key,
      @RequestBody ApprovalRequest request) {
    String projectId = queries.projectIdOf(principal.accountId(), deploymentId);
    DeploymentAccepted.requireKey(key);
    return DeploymentAccepted.from(
        deployments.decide(
            new DecisionRequest(
                principal.accountId(), projectId, deploymentId, request.toDecisions(), key)),
        projectId);
  }

  /** 취소 요청이에요 (WR-08). 접수가 실제 종료를 뜻하지 않아요 — apply 뒤에는 실행 서비스가 결과를 기다려요. */
  @PostMapping("/cancel")
  @Operation(
      summary = "배포 취소·중단 요청",
      description =
          "미제출 명령은 취소해요. apply가 제출됐거나 여부가 불명확하면 중단 요청만 기록하고 실제 종료를 기다려요. 강제 종료·즉시 롤백하지 않아요.")
  @ApiResponse(
      responseCode = "202",
      description = "요청 접수. 실제 상태는 배포 상세로 확인해요",
      useReturnTypeSchema = true)
  public ResponseEntity<DeploymentAccepted> cancel(
      @CurrentAccount AuthPrincipal principal,
      @PathVariable String deploymentId,
      @Parameter(required = true, description = "멱등 키. 1~255자")
          @RequestHeader(value = DeploymentAccepted.IDEMPOTENCY_KEY, required = false)
          String key,
      @RequestBody TargetSelection request) {
    String projectId = queries.projectIdOf(principal.accountId(), deploymentId);
    DeploymentAccepted.requireKey(key);
    return DeploymentAccepted.from(
        deployments.cancel(
            new ControlRequest(
                principal.accountId(), projectId, deploymentId, targets(request), key)),
        projectId);
  }

  /** 실패한 대상만 새 배포로 다시 시도해요 (W-05b·W-08). 경로는 10/2 웹·앱·승환이 합의했어요 (#42). */
  @Operation(summary = "실패 대상 재시도 — 새 배포를 만들어요")
  @PostMapping("/retry")
  @ApiResponse(
      responseCode = "201",
      description = "실패 대상의 새 배포예요. 원본 이력은 유지해요",
      useReturnTypeSchema = true)
  public ResponseEntity<DeploymentAccepted> retry(
      @CurrentAccount AuthPrincipal principal,
      @PathVariable String deploymentId,
      @Parameter(required = true, description = "멱등 키. 1~255자")
          @RequestHeader(value = DeploymentAccepted.IDEMPOTENCY_KEY, required = false)
          String key,
      @RequestBody TargetSelection request) {
    String projectId = queries.projectIdOf(principal.accountId(), deploymentId);
    DeploymentAccepted.requireKey(key);
    return DeploymentAccepted.from(
        deployments.retry(
            new ControlRequest(
                principal.accountId(), projectId, deploymentId, targets(request), key)),
        projectId);
  }

  /** 전체 성공한 원본에서 고른 대상만 새 배포로 되돌려요 (WR-14). 새 plan·승인을 거쳐요. */
  @PostMapping("/rollback")
  @Operation(
      summary = "성공 원본으로 롤백 배포 접수",
      description = "새 plan과 승인을 거쳐요. DB 데이터 복구는 아니며 원본 입력/대상 설정이 맞지 않으면 409예요.")
  @ApiResponse(responseCode = "201", description = "새 롤백 배포를 접수했어요", useReturnTypeSchema = true)
  public ResponseEntity<DeploymentAccepted> rollback(
      @CurrentAccount AuthPrincipal principal,
      @PathVariable String deploymentId,
      @Parameter(required = true, description = "멱등 키. 1~255자")
          @RequestHeader(value = DeploymentAccepted.IDEMPOTENCY_KEY, required = false)
          String key,
      @RequestBody RollbackSelection request) {
    String projectId = queries.projectIdOf(principal.accountId(), deploymentId);
    DeploymentAccepted.requireKey(key);
    return DeploymentAccepted.from(
        deployments.rollback(
            new RollbackRequest(
                principal.accountId(),
                projectId,
                deploymentId,
                request == null ? null : request.triggerDeploymentId(),
                request == null ? null : TargetLimit.check(request.targetIds()),
                request == null ? null : request.reason(),
                key)),
        projectId);
  }

  /**
   * 배포 이벤트 스트림이에요 (E-01).
   *
   * <p>재생·heartbeat·연결 수 제한은 승환의 SSE 기반이 맡아요. 여기서는 인증된 주체와 재연결 위치만 넘겨요.
   */
  @GetMapping(value = "/events", produces = MediaType.TEXT_EVENT_STREAM_VALUE)
  @Operation(
      summary = "배포 SSE",
      description =
          "채널별 seq를 id로 보내요. Last-Event-ID 이후 재생, heartbeat 15초, 재생 불가 시 resync예요. event_type은 선택 필터예요.")
  @ApiResponse(
      responseCode = "200",
      description = "SSE 스트림",
      content = @Content(mediaType = "text/event-stream", schema = @Schema(type = "string")))
  public SseEmitter deploymentEvents(
      @CurrentAccount AuthPrincipal principal,
      @PathVariable String deploymentId,
      @RequestHeader(value = "Last-Event-ID", required = false) String lastEventId,
      @RequestParam(value = "event_type", required = false) String eventType,
      HttpServletResponse response) {
    String projectId = queries.projectIdOf(principal.accountId(), deploymentId);
    response.setHeader(HttpHeaders.CACHE_CONTROL, "no-cache");
    return events.openDeployment(
        principal.accountId(), projectId, deploymentId, lastEventId, eventType);
  }

  private static List<String> targets(TargetSelection request) {
    return request == null ? null : TargetLimit.check(request.targetIds());
  }
}
