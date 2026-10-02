package com.teamdaisy.server.project.web;

import com.fasterxml.jackson.databind.JsonNode;
import com.teamdaisy.server.common.error.DaisyException;
import com.teamdaisy.server.common.error.ErrorCode;
import com.teamdaisy.server.identity.auth.AuthPrincipal;
import com.teamdaisy.server.identity.web.CurrentAccount;
import com.teamdaisy.server.project.application.ProjectRegistration;
import io.swagger.v3.oas.annotations.security.SecurityRequirement;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

/**
 * 프로젝트 연결·해제 API 예요 (WR-02·WR-13). 조회 컨트롤러는 클래스 전체가 읽기 전용 트랜잭션이라 쓰기는 여기로 나눠요.
 *
 * <p>{@code manifest} 는 null 이에요. {@code deploy.yaml} 스키마가 정해지고 서버가 저장소를 읽게 되면 채워요 (WR-03).
 */
@RestController
@SecurityRequirement(name = "bearerAuth")
public class ProjectCreateController {
  private final ProjectRegistration registration;

  public ProjectCreateController(ProjectRegistration registration) {
    this.registration = registration;
  }

  /** 연결 요청이에요. {@code repository} 는 {@code owner/repo} 나 GitHub URL 이에요. */
  public record CreateProject(String repository, String branch) {}

  /**
   * 연결 결과예요.
   *
   * @param manifest {@code deploy.yaml} 검증 결과. 지금은 검증하지 않아 null 이에요
   */
  public record ProjectCreated(ProjectResponse project, JsonNode manifest) {}

  @PostMapping("/projects")
  @ResponseStatus(HttpStatus.CREATED)
  public ProjectCreated create(
      @CurrentAccount AuthPrincipal principal, @RequestBody CreateProject request) {
    if (request == null) {
      throw new DaisyException(ErrorCode.VALIDATION_FAILED);
    }
    var project = registration.register(principal, request.repository(), request.branch());
    return new ProjectCreated(ProjectResponse.detail(project), null);
  }

  /**
   * 연결을 해제해요 (WR-13). 인프라는 지우지 않아요. 진행 중 배포가 있으면 409 예요.
   *
   * <p>확인 입력(환경 이름)은 화면에서 받아요.
   */
  @DeleteMapping("/projects/{projectId}")
  @ResponseStatus(HttpStatus.NO_CONTENT)
  public void disconnect(@CurrentAccount AuthPrincipal principal, @PathVariable String projectId) {
    registration.disconnect(principal, projectId);
  }
}
