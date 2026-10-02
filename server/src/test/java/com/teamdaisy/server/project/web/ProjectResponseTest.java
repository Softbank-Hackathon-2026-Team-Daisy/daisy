package com.teamdaisy.server.project.web;

import static org.assertj.core.api.Assertions.assertThat;

import com.teamdaisy.server.project.domain.Project;
import java.time.Instant;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

/** A-01·A-12 응답의 상세 전용 필드를 고정해요 (server/SPEC.md 「A-12 last_seq」). */
class ProjectResponseTest {
  private static final Project PROJECT =
      Project.connect(
          "prj_1",
          "sample-monolith",
          "o/sample-monolith",
          "https://github.com/o/sample-monolith",
          "main",
          "deploy.yaml",
          "acct_1",
          Instant.parse("2026-10-02T00:00:00Z"));

  @Test
  @DisplayName("상세는 프로젝트 채널 시작 지점 last_seq 를 주고, 목록은 비워요")
  void lastSeqOnlyInDetail() {
    assertThat(ProjectResponse.detail(PROJECT).lastSeq()).isEqualTo(0L);
    assertThat(ProjectResponse.summary(PROJECT).lastSeq()).isNull();
    assertThat(ProjectResponse.summary(PROJECT).repositoryUrl()).isNull();
  }
}
