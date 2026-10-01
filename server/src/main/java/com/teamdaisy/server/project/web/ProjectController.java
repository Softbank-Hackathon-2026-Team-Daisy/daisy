package com.teamdaisy.server.project.web;

import com.teamdaisy.server.common.error.DaisyException;
import com.teamdaisy.server.common.error.ErrorCode;
import com.teamdaisy.server.common.web.PageResponse;
import com.teamdaisy.server.identity.auth.AuthPrincipal;
import com.teamdaisy.server.identity.web.CurrentAccount;
import com.teamdaisy.server.project.access.ProjectAccessService;
import com.teamdaisy.server.project.domain.Project;
import com.teamdaisy.server.project.domain.ProjectRepository;
import java.util.List;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/** 프로젝트 조회예요. 생성·연결은 저장소 연결 절차가 정해진 뒤에 넣어요. */
@RestController
@RequestMapping("/projects")
@Transactional(readOnly = true)
public class ProjectController {
  private final ProjectRepository projects;
  private final ProjectAccessService access;

  public ProjectController(ProjectRepository projects, ProjectAccessService access) {
    this.projects = projects;
    this.access = access;
  }

  @GetMapping
  public PageResponse<ProjectResponse> list(@CurrentAccount AuthPrincipal principal) {
    List<ProjectResponse> items =
        projects.findAccessible(principal.accountId()).stream()
            .map(ProjectResponse::summary)
            .toList();
    return PageResponse.of(items);
  }

  @GetMapping("/{projectId}")
  public ProjectResponse detail(
      @CurrentAccount AuthPrincipal principal, @PathVariable String projectId) {
    // 접근 판정을 먼저 해요. 없는 프로젝트와 권한 없는 프로젝트가 모두 404 라 조회 결과로 존재를 알 수 없어요.
    access.requireRead(principal, projectId);
    Project project =
        projects.findById(projectId).orElseThrow(() -> new DaisyException(ErrorCode.NOT_FOUND));
    return ProjectResponse.detail(project);
  }
}
