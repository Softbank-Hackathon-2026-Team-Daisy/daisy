package com.teamdaisy.server.project.execution;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatCode;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ObjectNode;
import com.teamdaisy.server.common.error.DaisyException;
import com.teamdaisy.server.common.error.ErrorCode;
import com.teamdaisy.server.deployment.application.DeploymentExecutionService.BuildResult;
import com.teamdaisy.server.deployment.application.ExecutionInputs.BuildInput;
import com.teamdaisy.server.deployment.application.ExecutionInputs.Captured;
import com.teamdaisy.server.deployment.application.ExecutionInputs.FrozenInput;
import com.teamdaisy.server.deployment.application.ExecutionInputs.FrozenTarget;
import com.teamdaisy.server.project.domain.Project;
import com.teamdaisy.server.project.domain.ProjectRepository;
import com.teamdaisy.server.project.domain.SourceVersion;
import com.teamdaisy.server.project.domain.SourceVersionRepository;
import com.teamdaisy.server.project.domain.Target;
import com.teamdaisy.server.project.domain.TargetRepository;
import java.time.Instant;
import java.util.List;
import java.util.Optional;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.function.Executable;
import org.springframework.beans.BeanUtils;
import org.springframework.test.util.ReflectionTestUtils;

/**
 * 실행 입력 어댑터의 검사·스냅샷 모양을 고정해요 (server/SPEC.md ② · 검증 V2~V5).
 *
 * <p>핵심은 셋이에요. 받은 빌드 ID 하나만 쓰는 것, 자격증명을 참조 그대로 넘기는 것, 확인 결과는 받은 값이 아니라 DB 값이라는 것.
 */
class ExecutionInputsAdapterTest {
  private static final String PROJECT = "prj_1";
  private static final String OTHER = "prj_2";
  private static final String COMMIT = "a".repeat(40);
  private static final String DIGEST = "sha256:" + "b".repeat(64);
  private static final ObjectMapper MAPPER = new ObjectMapper();

  private final ProjectRepository projects = mock(ProjectRepository.class);
  private final TargetRepository targets = mock(TargetRepository.class);
  private final SourceVersionRepository builds = mock(SourceVersionRepository.class);
  private final ExecutionInputsAdapter adapter =
      new ExecutionInputsAdapter(projects, targets, builds, MAPPER);

  @BeforeEach
  void project() {
    Project project =
        Project.connect(
            PROJECT,
            "sample-monolith",
            "org/sample-monolith",
            "https://github.com/org/sample-monolith",
            "main",
            "deploy.yaml",
            "acc_o",
            Instant.now());
    ReflectionTestUtils.setField(project, "repositoryCredentialRef", "vault://repo/1");
    when(projects.findById(PROJECT)).thenReturn(Optional.of(project));
  }

  private static ObjectNode images(String commit, String digest) {
    ObjectNode web = MAPPER.createObjectNode();
    web.put("image_ref", "docker.io/org/app:" + commit);
    web.put("commit_sha", commit);
    if (digest != null) {
      web.put("digest", digest);
    }
    ObjectNode images = MAPPER.createObjectNode();
    images.set("web", web);
    return images;
  }

  private SourceVersion givenBuild(String id, String project, String status, JsonNode images) {
    SourceVersion build = BeanUtils.instantiateClass(SourceVersion.class);
    ReflectionTestUtils.setField(build, "id", id);
    ReflectionTestUtils.setField(build, "projectId", project);
    ReflectionTestUtils.setField(build, "commitSha", COMMIT);
    ReflectionTestUtils.setField(build, "status", status);
    ReflectionTestUtils.setField(build, "imageRefs", images);
    when(builds.findById(id)).thenReturn(Optional.of(build));
    return build;
  }

  private Target givenTarget(String id, String project, String connection) {
    ObjectNode config = MAPPER.createObjectNode().put("region", "ap-northeast-2");
    Target target =
        Target.create(
            id, project, id + "-name", "aws", "state/" + id, config, connection, Instant.now());
    ReflectionTestUtils.setField(target, "credentialRef", "vault://aws/1");
    ReflectionTestUtils.setField(target, "credentialVersion", "v3");
    when(targets.findById(id)).thenReturn(Optional.of(target));
    return target;
  }

  private Captured capture(List<String> targetIds, JsonNode input) {
    return adapter.capture("acc_o", PROJECT, "src_1", targetIds, input);
  }

  private static void assertCode(Executable call, ErrorCode code) {
    assertThatThrownBy(call::execute)
        .isInstanceOf(DaisyException.class)
        .extracting(exception -> ((DaisyException) exception).errorCode())
        .isEqualTo(code);
  }

  // ── capture ─────────────────────────────────────────────

  @Test
  @DisplayName("성공 빌드와 대상을 설계 키 그대로 고정해요 — 자격증명은 참조 그대로예요")
  void captureSnapshots() {
    givenBuild("src_1", PROJECT, "succeeded", images(COMMIT, DIGEST));
    givenTarget("tgt_aws", PROJECT, "unknown");

    Captured captured = capture(List.of("tgt_aws"), null);

    assertThat(captured.repository().get("repository_url").asText())
        .isEqualTo("https://github.com/org/sample-monolith");
    assertThat(captured.repository().get("repository_credential_ref").asText())
        .isEqualTo("vault://repo/1");
    assertThat(captured.commonInput().get("hash_format_version").asInt()).isEqualTo(1);
    assertThat(captured.commonInput().get("strategy").asText()).isEqualTo("recreate");
    JsonNode snapshot = captured.targets().get(0).snapshot();
    assertThat(snapshot.get("credential_ref").asText()).isEqualTo("vault://aws/1");
    assertThat(snapshot.get("credential_version").asText()).isEqualTo("v3");
    assertThat(snapshot.get("config_revision").asLong()).isEqualTo(1L);
    assertThat(snapshot.get("config").get("region").asText()).isEqualTo("ap-northeast-2");
    assertThat(captured.targets().get(0).stateIdentity()).isEqualTo("state/tgt_aws");
    assertThat(captured.source().sourceVersionId()).isEqualTo("src_1");
    assertThat(captured.source().commitSha()).isEqualTo(COMMIT);
  }

  @Test
  @DisplayName("다른 프로젝트 빌드·없는 빌드는 구분 없이 404 예요")
  void foreignBuildIsNotFound() {
    givenBuild("src_1", OTHER, "succeeded", images(COMMIT, DIGEST));
    givenTarget("tgt_aws", PROJECT, "unknown");
    assertCode(() -> capture(List.of("tgt_aws"), null), ErrorCode.NOT_FOUND);

    when(builds.findById("src_1")).thenReturn(Optional.empty());
    assertCode(() -> capture(List.of("tgt_aws"), null), ErrorCode.NOT_FOUND);
  }

  @Test
  @DisplayName("성공하지 않은 빌드는 409 예요")
  void runningBuildConflicts() {
    givenBuild("src_1", PROJECT, "running", images(COMMIT, DIGEST));
    givenTarget("tgt_aws", PROJECT, "unknown");

    assertCode(() -> capture(List.of("tgt_aws"), null), ErrorCode.STATE_CONFLICT);
  }

  @Test
  @DisplayName("image_refs 의 commit 이 빌드와 다르거나 비어 있으면 409 예요")
  void imageRefsMustMatchBuild() {
    givenTarget("tgt_aws", PROJECT, "unknown");
    givenBuild("src_1", PROJECT, "succeeded", images("c".repeat(40), DIGEST));
    assertCode(() -> capture(List.of("tgt_aws"), null), ErrorCode.STATE_CONFLICT);

    givenBuild("src_1", PROJECT, "succeeded", null);
    assertCode(() -> capture(List.of("tgt_aws"), null), ErrorCode.STATE_CONFLICT);
  }

  @Test
  @DisplayName("다른 프로젝트 대상·보관된 대상은 404 예요")
  void foreignOrArchivedTargetIsNotFound() {
    givenBuild("src_1", PROJECT, "succeeded", images(COMMIT, DIGEST));
    givenTarget("tgt_x", OTHER, "unknown");
    assertCode(() -> capture(List.of("tgt_x"), null), ErrorCode.NOT_FOUND);

    Target archived = givenTarget("tgt_old", PROJECT, "unknown");
    ReflectionTestUtils.setField(archived, "archivedAt", Instant.now());
    assertCode(() -> capture(List.of("tgt_old"), null), ErrorCode.NOT_FOUND);
  }

  @Test
  @DisplayName("disconnected 대상은 409, unknown 은 허용해요 (확인 ⑤)")
  void disconnectedTargetConflicts() {
    givenBuild("src_1", PROJECT, "succeeded", images(COMMIT, DIGEST));
    givenTarget("tgt_off", PROJECT, "disconnected");
    givenTarget("tgt_aws", PROJECT, "unknown");

    assertCode(() -> capture(List.of("tgt_off"), null), ErrorCode.STATE_CONFLICT);
    assertThatCode(() -> capture(List.of("tgt_aws"), null)).doesNotThrowAnyException();
  }

  @Test
  @DisplayName("input 은 strategy=recreate 만 받아요 — hash_format_version·다른 키·다른 전략은 400")
  void inputIsRestricted() {
    givenBuild("src_1", PROJECT, "succeeded", images(COMMIT, DIGEST));
    givenTarget("tgt_aws", PROJECT, "unknown");

    assertCode(
        () -> capture(List.of("tgt_aws"), MAPPER.createObjectNode().put("hash_format_version", 2)),
        ErrorCode.VALIDATION_FAILED);
    assertCode(
        () -> capture(List.of("tgt_aws"), MAPPER.createObjectNode().put("secret", "x")),
        ErrorCode.VALIDATION_FAILED);
    assertCode(
        () -> capture(List.of("tgt_aws"), MAPPER.createObjectNode().put("strategy", "canary")),
        ErrorCode.VALIDATION_FAILED);
    assertThatCode(
            () ->
                capture(List.of("tgt_aws"), MAPPER.createObjectNode().put("strategy", "recreate")))
        .doesNotThrowAnyException();
  }

  @Test
  @DisplayName("digest 는 없어도 되지만 있으면 sha256:64hex 여야 해요")
  void digestFormat() {
    assertThat(ExecutionInputsAdapter.validImageRefs(images(COMMIT, null), COMMIT)).isTrue();
    assertThat(ExecutionInputsAdapter.validImageRefs(images(COMMIT, DIGEST), COMMIT)).isTrue();
    assertThat(ExecutionInputsAdapter.validImageRefs(images(COMMIT, "sha256:short"), COMMIT))
        .isFalse();
    assertThat(ExecutionInputsAdapter.validImageRefs(MAPPER.createObjectNode(), COMMIT)).isFalse();
  }

  // ── projectName ─────────────────────────────────────────

  @Test
  @DisplayName("프로젝트 이름을 돌려주고, 없으면 404 예요")
  void projectName() {
    assertThat(adapter.projectName(PROJECT)).isEqualTo("sample-monolith");
    when(projects.findById("prj_x")).thenReturn(Optional.empty());
    assertCode(() -> adapter.projectName("prj_x"), ErrorCode.NOT_FOUND);
  }

  // ── verifyFrozen ────────────────────────────────────────

  private FrozenInput frozenFor(Target target) {
    givenBuild("src_1", PROJECT, "succeeded", images(COMMIT, DIGEST));
    Captured captured = capture(List.of(target.id()), null);
    var input = captured.targets().get(0);
    return new FrozenInput(
        "dep_1",
        PROJECT,
        COMMIT,
        captured.repository(),
        captured.commonInput(),
        captured.source(),
        List.of(
            new FrozenTarget(
                "dt_1", input.id(), input.snapshot(), input.stateIdentity(), null, null)));
  }

  @Test
  @DisplayName("고정 뒤 아무것도 안 바뀌었으면 통과해요")
  void frozenUnchangedPasses() {
    Target target = givenTarget("tgt_aws", PROJECT, "unknown");
    FrozenInput frozen = frozenFor(target);

    assertThatCode(() -> adapter.verifyFrozen("acc_o", PROJECT, frozen)).doesNotThrowAnyException();
  }

  @Test
  @DisplayName("대상 보관·state_identity 변경·설정 revision 변경·빌드 상태 변경은 409 예요")
  void frozenDriftConflicts() {
    Target target = givenTarget("tgt_aws", PROJECT, "unknown");
    FrozenInput frozen = frozenFor(target);

    ReflectionTestUtils.setField(target, "stateIdentity", "state/other");
    assertCode(() -> adapter.verifyFrozen("acc_o", PROJECT, frozen), ErrorCode.STATE_CONFLICT);
    ReflectionTestUtils.setField(target, "stateIdentity", "state/tgt_aws");

    ReflectionTestUtils.setField(target, "configRevision", 2L);
    assertCode(() -> adapter.verifyFrozen("acc_o", PROJECT, frozen), ErrorCode.STATE_CONFLICT);
    ReflectionTestUtils.setField(target, "configRevision", 1L);

    ReflectionTestUtils.setField(target, "archivedAt", Instant.now());
    assertCode(() -> adapter.verifyFrozen("acc_o", PROJECT, frozen), ErrorCode.STATE_CONFLICT);
    ReflectionTestUtils.setField(target, "archivedAt", null);

    givenBuild("src_1", PROJECT, "failed", images(COMMIT, DIGEST));
    assertCode(() -> adapter.verifyFrozen("acc_o", PROJECT, frozen), ErrorCode.STATE_CONFLICT);
  }

  @Test
  @DisplayName("다른 프로젝트의 고정 입력은 409 예요")
  void frozenProjectMismatch() {
    Target target = givenTarget("tgt_aws", PROJECT, "unknown");
    FrozenInput frozen = frozenFor(target);

    assertCode(() -> adapter.verifyFrozen("acc_o", OTHER, frozen), ErrorCode.STATE_CONFLICT);
  }

  // ── recordBuild ─────────────────────────────────────────

  private static BuildResult result(String sourceVersionId, String commit, JsonNode images) {
    return new BuildResult(
        PROJECT,
        "dep_1",
        "exe_1",
        "jenkins",
        "evt_1",
        sourceVersionId,
        commit,
        images,
        Instant.now());
  }

  @Test
  @DisplayName("확인 결과는 받은 값이 아니라 DB 에 저장된 값이에요")
  void recordBuildReturnsStoredValue() {
    givenBuild("src_1", PROJECT, "succeeded", images(COMMIT, DIGEST));

    BuildInput stored = adapter.recordBuild(result("src_1", COMMIT, images(COMMIT, null)));

    assertThat(stored.imageRefs()).isEqualTo(images(COMMIT, DIGEST));
    assertThat(stored.imageRefs()).isNotEqualTo(images(COMMIT, null));
  }

  @Test
  @DisplayName("빌드 ID 없음·commit 불일치·image_refs 없음은 409 이고 NPE 가 나지 않아요")
  void recordBuildConflicts() {
    assertCode(() -> adapter.recordBuild(result(null, COMMIT, null)), ErrorCode.STATE_CONFLICT);
    assertCode(() -> adapter.recordBuild(null), ErrorCode.STATE_CONFLICT);

    givenBuild("src_1", PROJECT, "succeeded", images(COMMIT, DIGEST));
    assertCode(
        () -> adapter.recordBuild(result("src_1", "d".repeat(40), null)), ErrorCode.STATE_CONFLICT);

    givenBuild("src_1", PROJECT, "succeeded", null);
    assertCode(() -> adapter.recordBuild(result("src_1", COMMIT, null)), ErrorCode.STATE_CONFLICT);
  }
}
