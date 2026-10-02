package com.teamdaisy.server.project.web;

import com.teamdaisy.server.common.error.DaisyException;
import com.teamdaisy.server.common.error.ErrorCode;
import com.teamdaisy.server.common.web.PageResponse;
import com.teamdaisy.server.identity.auth.AuthPrincipal;
import com.teamdaisy.server.identity.web.CurrentAccount;
import com.teamdaisy.server.project.access.ProjectAccessService;
import com.teamdaisy.server.project.application.ScriptReader;
import io.swagger.v3.oas.annotations.security.SecurityRequirement;
import java.time.Clock;
import java.time.Instant;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/** 검증된 스크립트 목록 API 예요 (WR-10). 파일 내용(WR-07)은 서버에 없어서 여기 없어요. */
@RestController
@SecurityRequirement(name = "bearerAuth")
public class ScriptController {
  private final ProjectAccessService access;
  private final ScriptReader scripts;
  private final Clock clock;

  public ScriptController(ProjectAccessService access, ScriptReader scripts, Clock clock) {
    this.access = access;
    this.scripts = scripts;
    this.clock = clock;
  }

  /** 대상 순, 버전 내림차순이에요. {@code target_id} 를 주면 그 대상만이에요. */
  @GetMapping("/projects/{projectId}/scripts")
  public PageResponse<ScriptResponse> list(
      @CurrentAccount AuthPrincipal principal,
      @PathVariable String projectId,
      @RequestParam(name = "target_id", required = false) String targetId) {
    access.requireRead(principal, projectId);
    if (targetId != null && !scripts.hasTarget(projectId, targetId)) {
      throw new DaisyException(ErrorCode.NOT_FOUND);
    }
    Instant now = clock.instant();
    return new PageResponse<>(
        scripts.list(projectId, targetId).stream().map(row -> ScriptResponse.of(row, now)).toList(),
        null);
  }
}
