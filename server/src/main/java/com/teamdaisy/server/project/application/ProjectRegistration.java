package com.teamdaisy.server.project.application;

import com.teamdaisy.server.common.error.DaisyException;
import com.teamdaisy.server.common.error.ErrorCode;
import com.teamdaisy.server.identity.auth.AuthPrincipal;
import com.teamdaisy.server.project.access.ProjectAccessService;
import com.teamdaisy.server.project.domain.Project;
import com.teamdaisy.server.project.domain.ProjectMember;
import com.teamdaisy.server.project.domain.ProjectMemberRepository;
import com.teamdaisy.server.project.domain.ProjectRepository;
import java.time.Clock;
import java.time.Instant;
import java.util.UUID;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;

/**
 * GitHub 저장소를 프로젝트로 연결해요 (WR-02).
 *
 * <p>저장소가 실제로 있는지는 GitHub 에 묻지 않아요. 모르는 것을 확인한 것처럼 보이지 않게 {@code deploy.yaml} 검증 결과도 비워 둬요 (WR-03
 * 스키마 결정 대기). 새 프로젝트에는 배포 대상이 없어요 — 대상 등록은 범위가 정해지지 않았어요.
 */
@Component
public class ProjectRegistration {
  private static final Pattern GITHUB =
      Pattern.compile(
          "^(?:https://github\\.com/)?([A-Za-z0-9](?:[A-Za-z0-9-]{0,38}))/([A-Za-z0-9._-]{1,100}?)(?:\\.git)?/?$");
  private static final Pattern BRANCH = Pattern.compile("[A-Za-z0-9._/-]{1,255}");
  private static final String MANIFEST_PATH = "deploy.yaml";

  private final ProjectRepository projects;
  private final ProjectMemberRepository members;
  private final ProjectAccessService access;
  private final Clock clock;

  public ProjectRegistration(
      ProjectRepository projects,
      ProjectMemberRepository members,
      ProjectAccessService access,
      Clock clock) {
    this.projects = projects;
    this.members = members;
    this.access = access;
    this.clock = clock;
  }

  /** {@code owner/repo} 로 맞춘 저장소예요. */
  public record Repository(String owner, String name) {
    public String id() {
      return owner + "/" + name;
    }

    public String url() {
      return "https://github.com/" + id();
    }
  }

  @Transactional
  public Project register(AuthPrincipal principal, String repository, String branch) {
    access.requireWriter(principal);
    Repository repo = parseRepository(repository);
    String defaultBranch = parseBranch(branch);
    if (projects.existsByRepositoryIdAndArchivedAtIsNull(repo.id())) {
      throw new DaisyException(ErrorCode.STATE_CONFLICT);
    }
    Instant now = clock.instant();
    String id = "prj_" + UUID.randomUUID();
    Project project =
        projects.save(
            Project.connect(
                id,
                repo.name(),
                repo.id(),
                repo.url(),
                defaultBranch,
                MANIFEST_PATH,
                principal.accountId(),
                now));
    members.save(ProjectMember.grant(id, principal.accountId(), principal.accountId(), now));
    return project;
  }

  /** {@code owner/repo} 나 {@code https://github.com/owner/repo(.git)} 만 받아요. 다른 호스트는 400 이에요. */
  static Repository parseRepository(String value) {
    if (value == null) {
      throw invalid();
    }
    Matcher matcher = GITHUB.matcher(value.trim());
    if (!matcher.matches() || matcher.group(2).equals(".") || matcher.group(2).equals("..")) {
      throw invalid();
    }
    return new Repository(matcher.group(1), matcher.group(2));
  }

  /** git 브랜치 이름으로 안전한 글자만 받아요. {@code -}·{@code /} 로 시작하거나 {@code ..} 가 있으면 400 이에요. */
  static String parseBranch(String value) {
    if (value == null) {
      throw invalid();
    }
    String branch = value.trim();
    if (!BRANCH.matcher(branch).matches()
        || branch.startsWith("-")
        || branch.startsWith("/")
        || branch.endsWith("/")
        || branch.contains("..")
        || branch.contains("//")) {
      throw invalid();
    }
    return branch;
  }

  private static DaisyException invalid() {
    return new DaisyException(ErrorCode.VALIDATION_FAILED);
  }
}
