package com.teamdaisy.server.project.access;

import static org.assertj.core.api.Assertions.assertThatCode;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

import com.teamdaisy.server.common.error.DaisyException;
import com.teamdaisy.server.common.error.ErrorCode;
import com.teamdaisy.server.identity.domain.Account;
import com.teamdaisy.server.identity.domain.AccountRepository;
import com.teamdaisy.server.project.domain.ProjectMember;
import com.teamdaisy.server.project.domain.ProjectMemberRepository;
import com.teamdaisy.server.project.domain.ProjectRepository;
import java.time.Instant;
import java.util.Optional;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.test.util.ReflectionTestUtils;

/**
 * 실행 서비스가 부르는 접근 검사가 기존 판정(404·403)을 그대로 따르는지 고정해요.
 *
 * <p>실행 서비스는 계정 ID 만 넘겨요. 그 계정의 역할·활성 여부를 DB 에서 다시 읽는 것이 핵심이에요.
 */
class ExecutionAccessAdapterTest {
  private static final String PROJECT = "prj_1";

  private final AccountRepository accounts = mock(AccountRepository.class);
  private final ProjectRepository projects = mock(ProjectRepository.class);
  private final ProjectMemberRepository members = mock(ProjectMemberRepository.class);
  private final ExecutionAccessAdapter adapter =
      new ExecutionAccessAdapter(accounts, new ProjectAccessService(projects, members));

  private void givenAccount(String id, String role, boolean disabled) {
    Account account = Account.create(id, id, "hash", id, role, Instant.now());
    if (disabled) {
      ReflectionTestUtils.setField(account, "disabledAt", Instant.now());
    }
    when(accounts.findById(id)).thenReturn(Optional.of(account));
  }

  private void givenMember(String accountId) {
    when(projects.existsById(PROJECT)).thenReturn(true);
    when(members.findByIdProjectIdAndIdAccountId(PROJECT, accountId))
        .thenReturn(Optional.of(ProjectMember.grant(PROJECT, accountId, "acc_o", Instant.now())));
  }

  private static ErrorCode codeOf(Throwable exception) {
    return ((DaisyException) exception).errorCode();
  }

  @Test
  @DisplayName("멤버인 owner 는 조회·변경 모두 통과해요")
  void ownerPasses() {
    givenAccount("acc_o", "owner", false);
    givenMember("acc_o");

    assertThatCode(() -> adapter.requireRead("acc_o", PROJECT)).doesNotThrowAnyException();
    assertThatCode(() -> adapter.requireWrite("acc_o", PROJECT)).doesNotThrowAnyException();
  }

  @Test
  @DisplayName("멤버인 viewer 는 조회는 되고 변경은 403 이에요")
  void viewerCannotWrite() {
    givenAccount("acc_v", "viewer", false);
    givenMember("acc_v");

    assertThatCode(() -> adapter.requireRead("acc_v", PROJECT)).doesNotThrowAnyException();
    assertThatThrownBy(() -> adapter.requireWrite("acc_v", PROJECT))
        .extracting(ExecutionAccessAdapterTest::codeOf)
        .isEqualTo(ErrorCode.FORBIDDEN);
  }

  @Test
  @DisplayName("비멤버는 owner 여도 404 예요")
  void nonMemberIsNotFound() {
    givenAccount("acc_o", "owner", false);
    when(projects.existsById(PROJECT)).thenReturn(true);
    when(members.findByIdProjectIdAndIdAccountId(PROJECT, "acc_o")).thenReturn(Optional.empty());

    assertThatThrownBy(() -> adapter.requireWrite("acc_o", PROJECT))
        .extracting(ExecutionAccessAdapterTest::codeOf)
        .isEqualTo(ErrorCode.NOT_FOUND);
  }

  @Test
  @DisplayName("비활성 계정은 멤버여도 401 이에요")
  void disabledAccountIsUnauthenticated() {
    givenAccount("acc_o", "owner", true);
    givenMember("acc_o");

    assertThatThrownBy(() -> adapter.requireRead("acc_o", PROJECT))
        .extracting(ExecutionAccessAdapterTest::codeOf)
        .isEqualTo(ErrorCode.UNAUTHENTICATED);
  }

  @Test
  @DisplayName("없는 계정·빈 계정 ID 는 401 이에요")
  void unknownActorIsUnauthenticated() {
    when(accounts.findById("acc_x")).thenReturn(Optional.empty());

    assertThatThrownBy(() -> adapter.requireRead("acc_x", PROJECT))
        .extracting(ExecutionAccessAdapterTest::codeOf)
        .isEqualTo(ErrorCode.UNAUTHENTICATED);
    assertThatThrownBy(() -> adapter.requireRead(" ", PROJECT))
        .extracting(ExecutionAccessAdapterTest::codeOf)
        .isEqualTo(ErrorCode.UNAUTHENTICATED);
  }

  @Test
  @DisplayName("역할은 계정 ID 로 DB 에서 다시 읽어요 — 바뀐 역할이 바로 반영돼요")
  void roleIsReadFromDatabase() {
    givenAccount("acc_o", "owner", false);
    givenMember("acc_o");
    assertThatCode(() -> adapter.requireWrite("acc_o", PROJECT)).doesNotThrowAnyException();

    givenAccount("acc_o", "viewer", false);
    assertThatThrownBy(() -> adapter.requireWrite("acc_o", PROJECT))
        .extracting(ExecutionAccessAdapterTest::codeOf)
        .isEqualTo(ErrorCode.FORBIDDEN);
  }
}
