package com.teamdaisy.server.project.application;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.teamdaisy.server.common.error.DaisyException;
import com.teamdaisy.server.common.error.ErrorCode;
import com.teamdaisy.server.project.application.BuildRegistry.BuildReport;
import java.time.Clock;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.mock.env.MockEnvironment;

/** CI 빌드 수신의 보낸 쪽 확인 규칙을 고정해요 (server/SPEC.md 「CI 빌드 수신」). */
class BuildReceiptTest {
  private static final String COMMIT = "a".repeat(40);

  private static BuildReceipt receipt(String mapping) {
    MockEnvironment env =
        new MockEnvironment()
            .withProperty("daisy.jenkins.instance-id", "unibloom-onprem")
            .withProperty("daisy.jenkins.ci-projects", mapping);
    return new BuildReceipt(null, null, env, new ObjectMapper(), Clock.systemUTC());
  }

  private static BuildReport report(String project, String source, String buildId) {
    return new BuildReport(
        project, source, buildId, COMMIT, "main", "running", null, null, null, null, null);
  }

  private static void assertCode(Runnable call, ErrorCode code) {
    assertThatThrownBy(call::run)
        .isInstanceOf(DaisyException.class)
        .extracting(exception -> ((DaisyException) exception).errorCode())
        .isEqualTo(code);
  }

  @Test
  @DisplayName("우리 인스턴스 source 와 매핑된 Job·프로젝트면 통과해요")
  void trustedPasses() {
    receipt("daisy-ci=prj_demo_monolith, team/daisy-ci-msa=prj_msa")
        .requireTrusted(report("prj_demo_monolith", "jenkins:unibloom-onprem", "daisy-ci#12"));
    receipt("daisy-ci=prj_demo_monolith, team/daisy-ci-msa=prj_msa")
        .requireTrusted(report("prj_msa", "jenkins:unibloom-onprem", "team/daisy-ci-msa#3"));
  }

  @Test
  @DisplayName("다른 인스턴스 source·매핑에 없는 Job·다른 프로젝트는 403, 빌드 ID 형식이 틀리면 400 이에요")
  void untrustedIsRejected() {
    var r = receipt("daisy-ci=prj_demo_monolith");
    assertCode(
        () -> r.requireTrusted(report("prj_demo_monolith", "jenkins:daisy-ci", "daisy-ci#12")),
        ErrorCode.FORBIDDEN);
    assertCode(
        () -> r.requireTrusted(report("prj_demo_monolith", "jenkins:unibloom-onprem", "other#1")),
        ErrorCode.FORBIDDEN);
    assertCode(
        () -> r.requireTrusted(report("prj_other", "jenkins:unibloom-onprem", "daisy-ci#12")),
        ErrorCode.FORBIDDEN);
    assertCode(
        () -> r.requireTrusted(report("prj_demo_monolith", "jenkins:unibloom-onprem", "daisy-ci")),
        ErrorCode.VALIDATION_FAILED);
  }

  @Test
  @DisplayName("매핑이 비어 있으면 모든 빌드를 막아요")
  void emptyMappingBlocksAll() {
    assertCode(
        () ->
            receipt("")
                .requireTrusted(
                    report("prj_demo_monolith", "jenkins:unibloom-onprem", "daisy-ci#1")),
        ErrorCode.FORBIDDEN);
    assertThat(BuildReceipt.jobProjects("a=1, =2, b=, c=3")).containsOnlyKeys("a", "c");
  }
}
