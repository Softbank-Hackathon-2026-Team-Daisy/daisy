package com.teamdaisy.server.project.web;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ObjectNode;
import com.teamdaisy.server.common.error.DaisyException;
import com.teamdaisy.server.common.error.ErrorCode;
import com.teamdaisy.server.deployment.application.DeploymentExecutionService;
import com.teamdaisy.server.deployment.application.DeploymentExecutionService.CreateRequest;
import com.teamdaisy.server.history.application.EventSseService;
import com.teamdaisy.server.idempotency.application.IdempotencyService;
import com.teamdaisy.server.identity.auth.AuthPrincipal;
import com.teamdaisy.server.identity.web.CurrentAccount;
import com.teamdaisy.server.project.access.ProjectAccessService;
import com.teamdaisy.server.project.domain.SourceVersionRepository;
import io.swagger.v3.oas.annotations.security.SecurityRequirement;
import jakarta.servlet.http.HttpServletResponse;
import java.util.List;
import java.util.Objects;
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
 * 프로젝트 경로의 배포 요청 API 예요. 배포 생성(WR-05)과 프로젝트 이벤트 SSE(E-02).
 *
 * <p><b>상태를 직접 바꾸지 않아요.</b> 검증한 요청을 승환의 실행 서비스로 넘기고, 현재 상태에서 허용되는지·멱등성은 실행 서비스가 판정해요
 * (server/docs/eh/roles.md §3). Jenkins 도 부르지 않아요.
 *
 * <p>트랜잭션을 걸지 않아요. 실행 서비스가 자기 트랜잭션을 열어요. 바깥에서 열면 실행 서비스의 실패가 바깥까지 롤백 전용으로 만들어요.
 */
@RestController
@RequestMapping("/projects/{projectId}")
@SecurityRequirement(name = "bearerAuth")
public class DeploymentRequestController {
  private static final int MAX_ID = 64;

  private final DeploymentExecutionService deployments;
  private final EventSseService events;
  private final ProjectAccessService access;
  private final SourceVersionRepository versions;
  private final ObjectMapper mapper;

  public DeploymentRequestController(
      DeploymentExecutionService deployments,
      EventSseService events,
      ProjectAccessService access,
      SourceVersionRepository versions,
      ObjectMapper mapper) {
    this.deployments = deployments;
    this.events = events;
    this.access = access;
    this.versions = versions;
    this.mapper = mapper;
  }

  /**
   * 배포 생성 요청이에요.
   *
   * @param sourceVersionId 배포할 빌드 (A-06 이 내보내는 ID). 필수예요
   * @param targetIds 배포할 대상 ID
   * @param commit 옛 계약 호환용이에요. 오면 그 빌드의 commit 과 같아야 해요. commit 만으로 빌드를 고르지 않아요
   * @param strategy 생략하면 {@code recreate}. 다른 값은 400 이에요
   */
  public record CreateDeployment(
      String sourceVersionId, List<String> targetIds, String commit, String strategy) {}

  /**
   * 배포를 접수해요 (WR-05).
   *
   * <p>권한을 먼저 봐요. 빌드의 commit 을 읽기 전에 막아야 다른 프로젝트 빌드의 존재가 응답 차이로 새지 않아요.
   */
  @PostMapping("/deployments")
  public ResponseEntity<DeploymentAccepted> create(
      @CurrentAccount AuthPrincipal principal,
      @PathVariable String projectId,
      @RequestHeader(value = DeploymentAccepted.IDEMPOTENCY_KEY, required = false)
          String idempotencyKey,
      @RequestBody CreateDeployment request) {
    access.requireWrite(principal, projectId);
    DeploymentAccepted.requireKey(idempotencyKey);
    if (request == null || blank(request.sourceVersionId())) {
      throw invalid();
    }
    if (request.sourceVersionId().length() > MAX_ID) {
      throw invalid();
    }
    requireCommitMatches(projectId, request);
    IdempotencyService.Response response =
        deployments.create(
            new CreateRequest(
                principal.accountId(),
                projectId,
                request.sourceVersionId(),
                TargetLimit.check(request.targetIds()),
                input(request.strategy()),
                idempotencyKey));
    return DeploymentAccepted.from(response, projectId);
  }

  /**
   * 프로젝트 이벤트 스트림이에요 (E-02).
   *
   * <p>재생·heartbeat·연결 수 제한은 승환의 SSE 기반이 맡아요. 여기서는 인증된 주체와 재연결 위치만 넘겨요.
   *
   * @param lastEventId 마지막으로 받은 이벤트 seq. 브라우저·앱이 재연결할 때 보내요
   * @param eventType 받을 이벤트 이름 하나. 생략하면 전부예요
   */
  @GetMapping(value = "/events", produces = MediaType.TEXT_EVENT_STREAM_VALUE)
  public SseEmitter projectEvents(
      @CurrentAccount AuthPrincipal principal,
      @PathVariable String projectId,
      @RequestHeader(value = "Last-Event-ID", required = false) String lastEventId,
      @RequestParam(value = "event_type", required = false) String eventType,
      HttpServletResponse response) {
    response.setHeader(HttpHeaders.CACHE_CONTROL, "no-cache");
    return events.openProject(principal.accountId(), projectId, lastEventId, eventType);
  }

  /** 옛 계약의 commit 이 같이 오면, 고른 빌드의 commit 과 같은지 봐요. 빌드가 없으면 여기서 판정하지 않고 실행 서비스의 404 에 맡겨요. */
  private void requireCommitMatches(String projectId, CreateDeployment request) {
    if (request.commit() == null) {
      return;
    }
    versions
        .findById(request.sourceVersionId())
        .filter(build -> Objects.equals(build.projectId(), projectId))
        .filter(build -> !Objects.equals(build.commitSha(), request.commit()))
        .ifPresent(
            mismatch -> {
              throw invalid();
            });
  }

  private ObjectNode input(String strategy) {
    ObjectNode node = mapper.createObjectNode();
    if (strategy != null) {
      node.put("strategy", strategy);
    }
    return node;
  }

  private static boolean blank(String value) {
    return value == null || value.isBlank();
  }

  private static DaisyException invalid() {
    return new DaisyException(ErrorCode.VALIDATION_FAILED);
  }
}
