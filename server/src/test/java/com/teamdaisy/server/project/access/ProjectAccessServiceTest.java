package com.teamdaisy.server.project.access;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

import com.teamdaisy.server.common.error.DaisyException;
import com.teamdaisy.server.common.error.ErrorCode;
import com.teamdaisy.server.identity.auth.AuthPrincipal;
import com.teamdaisy.server.project.domain.ProjectMember;
import com.teamdaisy.server.project.domain.ProjectMemberRepository;
import com.teamdaisy.server.project.domain.ProjectRepository;
import java.time.Instant;
import java.util.Optional;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

/**
 * 접근 판정이 404 와 403 을 구분하는지 고정해요.
 *
 * <p>없는 프로젝트와 권한 없는 프로젝트를 같은 404 로 돌려주는 것이 핵심이에요. 403 으로 나누면 다른 팀의 프로젝트가 존재한다는 사실이 샙니다.
 */
class ProjectAccessServiceTest {
  private static final String PROJECT = "prj_1";
  private static final AuthPrincipal OWNER = new AuthPrincipal("acc_1", "daisy", "owner");
  private static final AuthPrincipal VIEWER = new AuthPrincipal("acc_2", "judge", "viewer");

  private final ProjectRepository projects = mock(ProjectRepository.class);
  private final ProjectMemberRepository members = mock(ProjectMemberRepository.class);
  private final ProjectAccessService service = new ProjectAccessService(projects, members);

  private void givenProjectExists() {
    when(projects.existsById(PROJECT)).thenReturn(true);
  }

  private void givenMembership(AuthPrincipal principal, boolean revoked) {
    ProjectMember member =
        ProjectMember.grant(PROJECT, principal.accountId(), "acc_1", Instant.now());
    if (revoked) {
      // 철회된 멤버십은 행이 남아 있어도 접근이 안 돼야 해요.
      org.springframework.test.util.ReflectionTestUtils.setField(
          member, "revokedAt", Instant.now());
    }
    when(members.findByIdProjectIdAndIdAccountId(PROJECT, principal.accountId()))
        .thenReturn(Optional.of(member));
  }

  @Test
  @DisplayName("없는 프로젝트는 404예요")
  void missingProjectIsNotFound() {
    when(projects.existsById(PROJECT)).thenReturn(false);

    assertThatThrownBy(() -> service.requireRead(OWNER, PROJECT))
        .isInstanceOf(DaisyException.class)
        .extracting(exception -> ((DaisyException) exception).errorCode())
        .isEqualTo(ErrorCode.NOT_FOUND);
  }

  @Test
  @DisplayName("멤버가 아니면 403이 아니라 404예요")
  void nonMemberIsNotFound() {
    givenProjectExists();
    when(members.findByIdProjectIdAndIdAccountId(any(), any())).thenReturn(Optional.empty());

    assertThatThrownBy(() -> service.requireRead(OWNER, PROJECT))
        .isInstanceOf(DaisyException.class)
        .extracting(exception -> ((DaisyException) exception).errorCode())
        .isEqualTo(ErrorCode.NOT_FOUND);
  }

  @Test
  @DisplayName("철회된 멤버십은 접근할 수 없어요")
  void revokedMemberIsNotFound() {
    givenProjectExists();
    givenMembership(OWNER, true);

    assertThatThrownBy(() -> service.requireRead(OWNER, PROJECT))
        .isInstanceOf(DaisyException.class)
        .extracting(exception -> ((DaisyException) exception).errorCode())
        .isEqualTo(ErrorCode.NOT_FOUND);
  }

  @Test
  @DisplayName("멤버는 조회할 수 있어요")
  void memberCanRead() {
    givenProjectExists();
    givenMembership(OWNER, false);

    ProjectAccess access = service.requireRead(OWNER, PROJECT);

    assertThat(access.accountId()).isEqualTo("acc_1");
    assertThat(access.writable()).isTrue();
  }

  @Test
  @DisplayName("읽기 전용 계정도 조회는 되지만 변경은 403이에요")
  void viewerCanReadButNotWrite() {
    givenProjectExists();
    givenMembership(VIEWER, false);

    ProjectAccess access = service.requireRead(VIEWER, PROJECT);
    assertThat(access.writable()).isFalse();

    assertThatThrownBy(() -> service.requireWrite(VIEWER, PROJECT))
        .isInstanceOf(DaisyException.class)
        .extracting(exception -> ((DaisyException) exception).errorCode())
        .isEqualTo(ErrorCode.FORBIDDEN);
  }

  @Test
  @DisplayName("읽기 전용 계정은 멤버가 아닌 프로젝트에서도 404예요")
  void viewerOutsideProjectIsNotFound() {
    givenProjectExists();
    when(members.findByIdProjectIdAndIdAccountId(any(), any())).thenReturn(Optional.empty());

    // 권한 부족(403)보다 존재 비노출(404)이 먼저예요.
    assertThatThrownBy(() -> service.requireWrite(VIEWER, PROJECT))
        .isInstanceOf(DaisyException.class)
        .extracting(exception -> ((DaisyException) exception).errorCode())
        .isEqualTo(ErrorCode.NOT_FOUND);
  }

  @Test
  @DisplayName("프로젝트와 무관한 변경은 역할만 봐요")
  void requireWriterChecksRoleOnly() {
    service.requireWriter(OWNER);

    assertThatThrownBy(() -> service.requireWriter(VIEWER))
        .isInstanceOf(DaisyException.class)
        .extracting(exception -> ((DaisyException) exception).errorCode())
        .isEqualTo(ErrorCode.FORBIDDEN);
  }
}
