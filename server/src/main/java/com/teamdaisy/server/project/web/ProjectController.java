package com.teamdaisy.server.project.web;

import com.teamdaisy.server.common.error.DaisyException;
import com.teamdaisy.server.common.error.ErrorCode;
import com.teamdaisy.server.common.web.PageResponse;
import com.teamdaisy.server.identity.auth.AuthPrincipal;
import com.teamdaisy.server.identity.web.CurrentAccount;
import com.teamdaisy.server.project.access.ProjectAccessService;
import com.teamdaisy.server.project.domain.Project;
import com.teamdaisy.server.project.domain.ProjectRepository;
import com.teamdaisy.server.project.domain.SourceVersion;
import com.teamdaisy.server.project.domain.SourceVersionRepository;
import com.teamdaisy.server.project.domain.TargetRepository;
import java.util.List;
import org.springframework.data.domain.Limit;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/** 프로젝트 조회예요. 생성·연결은 저장소 연결 절차가 정해진 뒤에 넣어요. */
@RestController
@RequestMapping("/projects")
@Transactional(readOnly = true)
public class ProjectController {
  private static final int DEFAULT_LIMIT = 20;
  private static final int MAX_LIMIT = 100;

  private final ProjectRepository projects;
  private final TargetRepository targets;
  private final SourceVersionRepository versions;
  private final ProjectAccessService access;

  public ProjectController(
      ProjectRepository projects,
      TargetRepository targets,
      SourceVersionRepository versions,
      ProjectAccessService access) {
    this.projects = projects;
    this.targets = targets;
    this.versions = versions;
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

  /**
   * 환경별 현재 상태예요 (A-02). 앱 현황 화면이 이 경로만 써요.
   *
   * <p>집계하지 않아요. 배포 전체 상태 집계는 설계 2장대로 실행 서비스 소유라서, 여기서는 대상별 현재 값만 읽어 내보내요.
   *
   * <p>대상이 하나도 없으면 오류가 아니라 빈 목록이에요. 프로젝트에 환경을 아직 연결하지 않은 정상 상태예요.
   */
  @GetMapping("/{projectId}/targets/status")
  public PageResponse<TargetStatusResponse> targetStatus(
      @CurrentAccount AuthPrincipal principal, @PathVariable String projectId) {
    access.requireRead(principal, projectId);
    List<TargetStatusResponse> items =
        targets.findActiveByProject(projectId).stream().map(TargetStatusResponse::of).toList();
    return PageResponse.of(items);
  }

  /**
   * 빌드 목록이에요 (A-06). 앱 W-03 이미지 빌드 화면이 써요.
   *
   * <p>A-02 와 달리 실제 커서를 써요. 빌드는 커밋마다 쌓여서 목록이 자라고, 설계 5.5 가 {@code INDEX(project_id, received_at
   * DESC, id)} 를 그 용도로 두었어요.
   *
   * <p>수신(`POST`)은 승환 소유예요. 이 경로는 조회만 해요.
   */
  @GetMapping("/{projectId}/builds")
  public PageResponse<BuildResponse> builds(
      @CurrentAccount AuthPrincipal principal,
      @PathVariable String projectId,
      @RequestParam(required = false) String cursor,
      @RequestParam(required = false, defaultValue = "" + DEFAULT_LIMIT) int limit) {
    access.requireRead(principal, projectId);
    int size = normalizeLimit(limit);
    // 다음 페이지가 있는지 알려면 한 건 더 받아 봐야 해요. 따로 count 질의를 돌리지 않아요.
    Limit probe = Limit.of(size + 1);
    List<SourceVersion> rows =
        cursor == null
            ? versions.findFirstPage(projectId, probe)
            : fetchAfter(projectId, cursor, probe);

    boolean hasMore = rows.size() > size;
    List<SourceVersion> page = hasMore ? rows.subList(0, size) : rows;
    String nextCursor = null;
    if (hasMore) {
      SourceVersion last = page.get(page.size() - 1);
      nextCursor = new BuildCursor(last.receivedAt(), last.id()).encode();
    }
    return new PageResponse<>(page.stream().map(BuildResponse::of).toList(), nextCursor);
  }

  private List<SourceVersion> fetchAfter(String projectId, String cursor, Limit limit) {
    BuildCursor decoded = BuildCursor.decode(cursor);
    return versions.findAfterCursor(projectId, decoded.receivedAt(), decoded.id(), limit);
  }

  /**
   * {@code limit} 을 다듬어요. 최대값을 넘으면 400 이 아니라 깎아요 — 목록 조회가 한도 때문에 실패하지 않는 쪽이 나아요. 다만 0·음수는 요청이 잘못된
   * 것이라 막아요.
   */
  private static int normalizeLimit(int limit) {
    if (limit <= 0) {
      throw new DaisyException(ErrorCode.VALIDATION_FAILED);
    }
    return Math.min(limit, MAX_LIMIT);
  }
}
