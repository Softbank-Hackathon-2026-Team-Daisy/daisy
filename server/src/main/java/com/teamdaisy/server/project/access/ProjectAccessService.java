package com.teamdaisy.server.project.access;

import com.teamdaisy.server.common.error.DaisyException;
import com.teamdaisy.server.common.error.ErrorCode;
import com.teamdaisy.server.identity.auth.AuthPrincipal;
import com.teamdaisy.server.project.domain.ProjectMember;
import com.teamdaisy.server.project.domain.ProjectMemberRepository;
import com.teamdaisy.server.project.domain.ProjectRepository;
import java.util.Optional;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 프로젝트 접근과 변경 권한을 판정해요.
 *
 * <p>실행 서비스도 이 서비스를 호출해요. API 가 검사했다는 이유로 생략하지 않아요 (server/docs/eh/roles.md §3).
 *
 * <p>없는 프로젝트와 접근 권한이 없는 프로젝트를 모두 404 로 돌려줘요. 403 으로 구분하면 다른 팀의 프로젝트가 존재한다는 사실이 샙니다. 403 은 접근은 되는데
 * 역할이 모자란 경우에만 써요.
 */
@Service
@Transactional(readOnly = true)
public class ProjectAccessService {
  private final ProjectRepository projects;
  private final ProjectMemberRepository members;

  public ProjectAccessService(ProjectRepository projects, ProjectMemberRepository members) {
    this.projects = projects;
    this.members = members;
  }

  /** 조회 권한을 확인해요. 없거나 연결을 해제한(보관된) 프로젝트면 404 예요. */
  public ProjectAccess requireRead(AuthPrincipal principal, String projectId) {
    if (!projects.existsByIdAndArchivedAtIsNull(projectId)) {
      throw new DaisyException(ErrorCode.NOT_FOUND);
    }
    Optional<ProjectMember> member =
        members.findByIdProjectIdAndIdAccountId(projectId, principal.accountId());
    if (member.isEmpty() || !member.get().isActive()) {
      throw new DaisyException(ErrorCode.NOT_FOUND);
    }
    return new ProjectAccess(principal, projectId, !principal.readOnly());
  }

  /**
   * 변경·승인 권한을 확인해요.
   *
   * <p>접근은 되는데 읽기 전용 계정이면 403 이에요. 접근 자체가 안 되면 404 예요.
   */
  public ProjectAccess requireWrite(AuthPrincipal principal, String projectId) {
    ProjectAccess access = requireRead(principal, projectId);
    if (!access.writable()) {
      throw new DaisyException(ErrorCode.FORBIDDEN);
    }
    return access;
  }

  /** 프로젝트와 무관한 변경 요청(대상 등록 등)에서 역할만 확인해요. */
  public void requireWriter(AuthPrincipal principal) {
    if (principal.readOnly()) {
      throw new DaisyException(ErrorCode.FORBIDDEN);
    }
  }
}
