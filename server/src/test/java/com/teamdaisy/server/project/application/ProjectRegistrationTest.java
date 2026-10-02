package com.teamdaisy.server.project.application;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import com.teamdaisy.server.common.error.DaisyException;
import com.teamdaisy.server.common.error.ErrorCode;
import java.util.List;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

/** 프로젝트 연결 입력 규칙을 고정해요 (server/SPEC.md 「프로젝트 연결 WR-02」). */
class ProjectRegistrationTest {

  private static void assertInvalid(Runnable call) {
    assertThatThrownBy(call::run)
        .isInstanceOf(DaisyException.class)
        .extracting(exception -> ((DaisyException) exception).errorCode())
        .isEqualTo(ErrorCode.VALIDATION_FAILED);
  }

  @Test
  @DisplayName("owner/repo 와 GitHub URL 을 같은 owner/repo 로 맞춰요")
  void normalizesRepository() {
    for (String input :
        List.of(
            "Softbank-Hackathon-2026-Team-Daisy/sample-msa",
            "https://github.com/Softbank-Hackathon-2026-Team-Daisy/sample-msa",
            "https://github.com/Softbank-Hackathon-2026-Team-Daisy/sample-msa.git",
            "https://github.com/Softbank-Hackathon-2026-Team-Daisy/sample-msa/",
            "  Softbank-Hackathon-2026-Team-Daisy/sample-msa  ")) {
      var repo = ProjectRegistration.parseRepository(input);
      assertThat(repo.id()).as(input).isEqualTo("Softbank-Hackathon-2026-Team-Daisy/sample-msa");
      assertThat(repo.name()).isEqualTo("sample-msa");
      assertThat(repo.url())
          .isEqualTo("https://github.com/Softbank-Hackathon-2026-Team-Daisy/sample-msa");
    }
    assertThat(ProjectRegistration.parseRepository("o/my.app_v2").name()).isEqualTo("my.app_v2");
  }

  @Test
  @DisplayName("다른 호스트·잘못된 이름은 400 이에요")
  void rejectsBadRepository() {
    for (String input :
        List.of(
            "https://gitlab.com/o/r",
            "http://github.com/o/r",
            "o",
            "o/r/extra",
            "-o/r",
            "o/..",
            "o/.",
            "o r/x",
            "")) {
      assertInvalid(() -> ProjectRegistration.parseRepository(input));
    }
    assertInvalid(() -> ProjectRegistration.parseRepository(null));
  }

  @Test
  @DisplayName("브랜치는 안전한 글자만, 빈 값·-·/ 시작·.. 는 400 이에요")
  void branchRules() {
    assertThat(ProjectRegistration.parseBranch("main")).isEqualTo("main");
    assertThat(ProjectRegistration.parseBranch("release/v1.2")).isEqualTo("release/v1.2");
    for (String input : List.of("", " ", "-x", "/x", "x/", "a..b", "a//b", "a b", "a;rm")) {
      assertInvalid(() -> ProjectRegistration.parseBranch(input));
    }
    assertInvalid(() -> ProjectRegistration.parseBranch(null));
  }
}
