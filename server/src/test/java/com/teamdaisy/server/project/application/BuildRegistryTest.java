package com.teamdaisy.server.project.application;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ObjectNode;
import com.teamdaisy.server.common.error.DaisyException;
import com.teamdaisy.server.common.error.ErrorCode;
import com.teamdaisy.server.project.application.BuildRegistry.BuildReport;
import com.teamdaisy.server.project.application.BuildRegistry.Outcome;
import com.teamdaisy.server.project.application.BuildRegistry.Stored;
import java.time.Instant;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

/** 빌드 저장의 상태 전이·입력 규칙을 고정해요 (server/SPEC.md 「빌드 결과 저장」). */
class BuildRegistryTest {
  private static final ObjectMapper MAPPER = new ObjectMapper();
  private static final String COMMIT = "a".repeat(40);
  private static final Instant DONE = Instant.parse("2026-10-02T01:00:00.123456Z");

  private static ObjectNode images(String commit) {
    ObjectNode images = MAPPER.createObjectNode();
    images.putObject("web").put("image_ref", "ghcr.io/x/web:" + commit).put("commit_sha", commit);
    return images;
  }

  private static BuildReport report(String status) {
    return new BuildReport(
        "prj_1",
        "jenkins-1",
        "daisy-ci#7",
        COMMIT,
        "main",
        status,
        "succeeded".equals(status) ? images(COMMIT) : null,
        null,
        null,
        "succeeded".equals(status) || "failed".equals(status) ? DONE : null,
        null);
  }

  private static Stored stored(String status) {
    BuildReport r = report(status);
    return new Stored(
        "sv_1",
        r.projectId(),
        r.commitSha(),
        r.branch(),
        status,
        r.imageRefs(),
        null,
        null,
        r.finishedAt(),
        null);
  }

  private static void assertCode(Runnable call, ErrorCode code) {
    assertThatThrownBy(call::run)
        .isInstanceOf(DaisyException.class)
        .extracting(exception -> ((DaisyException) exception).errorCode())
        .isEqualTo(code);
  }

  @Test
  @DisplayName("앞으로 가면 갱신, 건너뛰어도 돼요")
  void forwardAndSkip() {
    assertThat(BuildRegistry.decide(stored("pending"), report("running")))
        .isEqualTo(Outcome.ADVANCE);
    assertThat(BuildRegistry.decide(stored("pending"), report("succeeded")))
        .isEqualTo(Outcome.ADVANCE);
    assertThat(BuildRegistry.decide(stored("running"), report("failed")))
        .isEqualTo(Outcome.ADVANCE);
  }

  @Test
  @DisplayName("뒤로 가는 보고는 무시해요")
  void regressionIsIgnored() {
    assertThat(BuildRegistry.decide(stored("succeeded"), report("running")))
        .isEqualTo(Outcome.UNCHANGED);
    assertThat(BuildRegistry.decide(stored("running"), report("pending")))
        .isEqualTo(Outcome.UNCHANGED);
  }

  @Test
  @DisplayName("같은 종료 결과는 무변경, 다른 종료 결과·다른 값은 409 예요")
  void terminalIsImmutable() {
    assertThat(BuildRegistry.decide(stored("succeeded"), report("succeeded")))
        .isEqualTo(Outcome.UNCHANGED);
    assertCode(
        () -> BuildRegistry.decide(stored("succeeded"), report("failed")),
        ErrorCode.STATE_CONFLICT);
    assertCode(
        () -> BuildRegistry.decide(stored("failed"), report("succeeded")),
        ErrorCode.STATE_CONFLICT);

    BuildReport otherImage =
        new BuildReport(
            "prj_1",
            "jenkins-1",
            "daisy-ci#7",
            COMMIT,
            "main",
            "succeeded",
            images(COMMIT).put("x", 1),
            null,
            null,
            DONE,
            null);
    assertCode(
        () -> BuildRegistry.decide(stored("succeeded"), otherImage), ErrorCode.STATE_CONFLICT);
  }

  @Test
  @DisplayName("같은 키인데 프로젝트·commit·브랜치가 다르면 409 예요")
  void identityConflict() {
    BuildReport r = report("running");
    assertCode(
        () ->
            BuildRegistry.decide(
                stored("pending"),
                new BuildReport(
                    "prj_2",
                    r.source(),
                    r.externalBuildId(),
                    COMMIT,
                    "main",
                    "running",
                    null,
                    null,
                    null,
                    null,
                    null)),
        ErrorCode.STATE_CONFLICT);
    assertCode(
        () ->
            BuildRegistry.decide(
                stored("pending"),
                new BuildReport(
                    "prj_1",
                    r.source(),
                    r.externalBuildId(),
                    "b".repeat(40),
                    "main",
                    "running",
                    null,
                    null,
                    null,
                    null,
                    null)),
        ErrorCode.STATE_CONFLICT);
    assertCode(
        () ->
            BuildRegistry.decide(
                stored("pending"),
                new BuildReport(
                    "prj_1",
                    r.source(),
                    r.externalBuildId(),
                    COMMIT,
                    "dev",
                    "running",
                    null,
                    null,
                    null,
                    null,
                    null)),
        ErrorCode.STATE_CONFLICT);
  }

  @Test
  @DisplayName("같은 진행 상태면 비어 있던 값만 채워요")
  void sameProgressFillsBlanks() {
    BuildReport withUrl =
        new BuildReport(
            "prj_1",
            "jenkins-1",
            "daisy-ci#7",
            COMMIT,
            "main",
            "running",
            null,
            "https://jenkins.test/job/daisy-ci/7/",
            null,
            null,
            null);
    assertThat(BuildRegistry.decide(stored("running"), withUrl)).isEqualTo(Outcome.FILL);
    assertThat(BuildRegistry.decide(stored("running"), report("running")))
        .isEqualTo(Outcome.UNCHANGED);
  }

  @Test
  @DisplayName("모양이 틀리면 400 이에요")
  void invalidShapes() {
    BuildReport ok = report("succeeded");
    assertThat(BuildRegistry.validate(ok).finishedAt()).isEqualTo(DONE);
    // 성공인데 이미지 없음 / 실패인데 이미지 / commit 이 다른 이미지 / 짧은 sha / 모르는 상태
    assertCode(
        () ->
            BuildRegistry.validate(
                new BuildReport(
                    "prj_1", "s", "e", COMMIT, null, "succeeded", null, null, null, null, null)),
        ErrorCode.VALIDATION_FAILED);
    assertCode(
        () ->
            BuildRegistry.validate(
                new BuildReport(
                    "prj_1",
                    "s",
                    "e",
                    COMMIT,
                    null,
                    "failed",
                    images(COMMIT),
                    null,
                    null,
                    null,
                    null)),
        ErrorCode.VALIDATION_FAILED);
    assertCode(
        () ->
            BuildRegistry.validate(
                new BuildReport(
                    "prj_1",
                    "s",
                    "e",
                    COMMIT,
                    null,
                    "succeeded",
                    images("c".repeat(40)),
                    null,
                    null,
                    null,
                    null)),
        ErrorCode.VALIDATION_FAILED);
    assertCode(
        () ->
            BuildRegistry.validate(
                new BuildReport(
                    "prj_1", "s", "e", "abc1234", null, "running", null, null, null, null, null)),
        ErrorCode.VALIDATION_FAILED);
    assertCode(
        () ->
            BuildRegistry.validate(
                new BuildReport(
                    "prj_1", "s", "e", COMMIT, null, "queued", null, null, null, null, null)),
        ErrorCode.VALIDATION_FAILED);
  }

  @Test
  @DisplayName("시각은 DB 정밀도(마이크로초)로 맞춰서, 같은 보고 재수신이 나노초 차이로 충돌하지 않아요")
  void timesAreTruncatedToMicros() {
    BuildReport nanos =
        new BuildReport(
            "prj_1", "s", "e", COMMIT, null, "failed", null, null, null, DONE.plusNanos(789), null);
    assertThat(BuildRegistry.validate(nanos).finishedAt()).isEqualTo(DONE);
  }

  @Test
  @DisplayName("상태가 없으면 내부 예외가 아니라 400 이에요 (#53 승환님 리뷰)")
  void missingStatusIsValidationFailure() {
    assertCode(
        () ->
            BuildRegistry.validate(
                new BuildReport(
                    "prj_1", "s", "e", COMMIT, null, null, null, null, null, null, null)),
        ErrorCode.VALIDATION_FAILED);
  }
}
