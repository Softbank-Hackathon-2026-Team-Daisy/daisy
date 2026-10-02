package com.teamdaisy.server.project.execution;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ObjectNode;
import com.teamdaisy.server.common.error.DaisyException;
import com.teamdaisy.server.common.error.ErrorCode;
import com.teamdaisy.server.deployment.application.DeploymentExecutionService.BuildResult;
import com.teamdaisy.server.deployment.application.ExecutionInputs;
import com.teamdaisy.server.project.domain.Project;
import com.teamdaisy.server.project.domain.ProjectRepository;
import com.teamdaisy.server.project.domain.SourceVersion;
import com.teamdaisy.server.project.domain.SourceVersionRepository;
import com.teamdaisy.server.project.domain.Target;
import com.teamdaisy.server.project.domain.TargetRepository;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.regex.Pattern;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;

/**
 * 실행 서비스가 배포 입력을 고정할 때 필요한 프로젝트·대상·빌드 정보를 줘요.
 *
 * <p>네 메서드 모두 호출한 쪽의 트랜잭션 안에서 <b>읽기만</b> 해요. 새 트랜잭션을 열지 않고, 추가 잠금을 걸지 않고, 외부 HTTP 를 부르지 않아요. 잠금 순서는
 * 실행 서비스가 쥐어요 (docs/execution-service-contract.md).
 *
 * <p>자격증명은 참조 문자열만 넘겨요. 복호화하지 않아요.
 *
 * <p>스냅샷 JSON 의 키는 설계 문서 338·339·364·664·665행을 따라요 (server/SPEC.md ②).
 */
@Component
@Transactional(readOnly = true)
public class ExecutionInputsAdapter implements ExecutionInputs {
  static final int HASH_FORMAT_VERSION = 1;
  static final String STRATEGY_RECREATE = "recreate";
  private static final String SUCCEEDED = "succeeded";
  private static final String DISCONNECTED = "disconnected";
  private static final Pattern DIGEST = Pattern.compile("sha256:[0-9a-f]{64}");

  private final ProjectRepository projects;
  private final TargetRepository targets;
  private final SourceVersionRepository builds;
  private final ObjectMapper mapper;

  public ExecutionInputsAdapter(
      ProjectRepository projects,
      TargetRepository targets,
      SourceVersionRepository builds,
      ObjectMapper mapper) {
    this.projects = projects;
    this.targets = targets;
    this.builds = builds;
    this.mapper = mapper;
  }

  /**
   * 선택한 빌드와 대상의 입력을 고정해요.
   *
   * <p>받은 {@code sourceVersionId} 하나만 봐요. commit 으로 다른 재빌드를 고르지 않아요. 다른 프로젝트의 빌드·대상과 없는 것을 구분하지 않고
   * 모두 404 예요.
   */
  @Override
  public Captured capture(
      String actorId,
      String projectId,
      String sourceVersionId,
      List<String> targetIds,
      JsonNode input) {
    Project project = projects.findById(projectId).orElseThrow(() -> fail(ErrorCode.NOT_FOUND));
    BuildInput source = succeededBuild(projectId, sourceVersionId, ErrorCode.NOT_FOUND);
    if (targetIds == null || targetIds.isEmpty()) {
      throw fail(ErrorCode.VALIDATION_FAILED);
    }
    List<TargetInput> selected = new ArrayList<>();
    for (String targetId : targetIds) {
      Target target = activeTarget(projectId, targetId, ErrorCode.NOT_FOUND);
      requireDeployable(target);
      selected.add(new TargetInput(target.id(), targetSnapshot(target), target.stateIdentity()));
    }
    return new Captured(repositorySnapshot(project), commonInput(input), selected, source);
  }

  /** 승인 대기 생성 때 고정할 프로젝트 이름이에요. */
  @Override
  public String projectName(String projectId) {
    return projects
        .findById(projectId)
        .map(Project::name)
        .orElseThrow(() -> fail(ErrorCode.NOT_FOUND));
  }

  /**
   * 재시도·롤백 때 저장된 입력이 지금도 유효한지 봐요.
   *
   * <p>권한은 실행 서비스가 앞에서 {@code requireWrite} 로 이미 확인해서 다시 보지 않아요. 어긋나면 모두 409 예요 — 요청이 틀린 게 아니라 그 사이
   * 상태가 바뀐 것이라서요.
   */
  @Override
  public void verifyFrozen(String actorId, String projectId, FrozenInput frozen) {
    if (frozen == null || !Objects.equals(projectId, frozen.projectId())) {
      throw fail(ErrorCode.STATE_CONFLICT);
    }
    if (frozen.targets() == null) {
      throw fail(ErrorCode.STATE_CONFLICT);
    }
    for (FrozenTarget item : frozen.targets()) {
      if (item == null) {
        throw fail(ErrorCode.STATE_CONFLICT);
      }
      Target target = activeTarget(projectId, item.targetId(), ErrorCode.STATE_CONFLICT);
      // 다른 state 에 apply 하게 되는 것을 막아요.
      if (!Objects.equals(target.stateIdentity(), item.stateIdentity())) {
        throw fail(ErrorCode.STATE_CONFLICT);
      }
      requireSameConfig(target, item.snapshot());
    }
    if (frozen.source() != null) {
      BuildInput current =
          succeededBuild(projectId, frozen.source().sourceVersionId(), ErrorCode.STATE_CONFLICT);
      if (!Objects.equals(current.commitSha(), frozen.source().commitSha())) {
        throw fail(ErrorCode.STATE_CONFLICT);
      }
    }
  }

  /**
   * 빌드 결과를 확인하고 <b>DB 에 저장된</b> 빌드 입력을 돌려줘요.
   *
   * <p>받은 값을 그대로 되돌려주지 않아요. 실행 서비스가 둘을 비교해 다르면 거절하게 하려는 거예요. {@code source_version} 에 쓰지 않아요
   * (server/SPEC.md 확인 ③).
   */
  @Override
  public BuildInput recordBuild(BuildResult result) {
    if (result == null || result.sourceVersionId() == null) {
      throw fail(ErrorCode.STATE_CONFLICT);
    }
    BuildInput stored =
        succeededBuild(result.projectId(), result.sourceVersionId(), ErrorCode.STATE_CONFLICT);
    if (!Objects.equals(stored.commitSha(), result.commitSha())) {
      throw fail(ErrorCode.STATE_CONFLICT);
    }
    return stored;
  }

  /**
   * 이 프로젝트의 성공 빌드만 돌려줘요.
   *
   * @param missing 없거나 다른 프로젝트일 때의 오류. 사용자가 고른 빌드면 404, 이미 고정된 빌드면 409 예요
   */
  private BuildInput succeededBuild(String projectId, String sourceVersionId, ErrorCode missing) {
    if (sourceVersionId == null || sourceVersionId.isBlank()) {
      throw fail(missing);
    }
    SourceVersion build =
        builds
            .findById(sourceVersionId)
            .filter(found -> Objects.equals(found.projectId(), projectId))
            .orElseThrow(() -> fail(missing));
    if (!SUCCEEDED.equals(build.status()) || build.commitSha() == null) {
      throw fail(ErrorCode.STATE_CONFLICT);
    }
    JsonNode images = build.imageRefs();
    if (!validImageRefs(images, build.commitSha())) {
      throw fail(ErrorCode.STATE_CONFLICT);
    }
    return new BuildInput(build.id(), build.commitSha(), images.deepCopy());
  }

  /**
   * 계약 모양 {@code {service: {image_ref, digest?, commit_sha}}} 인지 봐요.
   *
   * <p>모든 서비스의 {@code commit_sha} 가 빌드 commit 과 같아야 해요. digest 는 미확인이면 없어도 되지만, 있으면 {@code sha256:}
   * 과 64자리 hex 여야 해요.
   */
  static boolean validImageRefs(JsonNode images, String commit) {
    if (images == null || !images.isObject() || images.isEmpty()) {
      return false;
    }
    for (Map.Entry<String, JsonNode> entry : images.properties()) {
      JsonNode image = entry.getValue();
      if (entry.getKey().isBlank() || !image.isObject()) {
        return false;
      }
      JsonNode ref = image.get("image_ref");
      if (ref == null || !ref.isTextual() || ref.asText().isBlank()) {
        return false;
      }
      JsonNode sha = image.get("commit_sha");
      if (sha == null || !sha.isTextual() || !sha.asText().equals(commit)) {
        return false;
      }
      JsonNode digest = image.get("digest");
      if (digest != null
          && !digest.isNull()
          && (!digest.isTextual() || !DIGEST.matcher(digest.asText()).matches())) {
        return false;
      }
    }
    return true;
  }

  private Target activeTarget(String projectId, String targetId, ErrorCode missing) {
    if (targetId == null || targetId.isBlank()) {
      throw fail(missing);
    }
    return targets
        .findById(targetId)
        .filter(found -> Objects.equals(found.projectId(), projectId) && !found.isArchived())
        .orElseThrow(() -> fail(missing));
  }

  /**
   * 연결이 끊긴 것으로 확인된 대상은 고를 수 없어요 (server/SPEC.md 확인 ⑤).
   *
   * <p>연결 확인 기능이 아직 없어서 모든 대상이 {@code unknown} 이에요. {@code unknown} 까지 막으면 아무것도 배포할 수 없어서 허용해요.
   */
  private static void requireDeployable(Target target) {
    if (DISCONNECTED.equals(target.connectionState())) {
      throw fail(ErrorCode.STATE_CONFLICT);
    }
  }

  /**
   * 고정 뒤 대상 설정·자격증명 버전이 바뀌었으면 막아요 (server/SPEC.md 확인 ②).
   *
   * <p>재시도는 고정 입력을 그대로 쓰는 것인데, 그 입력이 이미 낡았으면 조용히 옛 설정으로 apply 하지 않게 해요. 정책이 바뀌면 이 메서드만 고치면 돼요.
   */
  private static void requireSameConfig(Target target, JsonNode snapshot) {
    if (snapshot == null || !snapshot.isObject()) {
      throw fail(ErrorCode.STATE_CONFLICT);
    }
    JsonNode revision = snapshot.get("config_revision");
    if (revision == null
        || !revision.canConvertToLong()
        || revision.asLong() != target.configRevision()) {
      throw fail(ErrorCode.STATE_CONFLICT);
    }
    JsonNode version = snapshot.get("credential_version");
    String frozenVersion = version == null || version.isNull() ? null : version.asText();
    if (!Objects.equals(frozenVersion, target.credentialVersion())) {
      throw fail(ErrorCode.STATE_CONFLICT);
    }
  }

  /** 설계 338·664행: 저장소 ID·URL·브랜치·manifest 경로·자격증명 참조. */
  private ObjectNode repositorySnapshot(Project project) {
    ObjectNode node = mapper.createObjectNode();
    node.put("repository_id", project.repositoryId());
    node.put("repository_url", project.repositoryUrl());
    node.put("default_branch", project.defaultBranch());
    node.put("manifest_path", project.manifestPath());
    node.put("repository_credential_ref", project.repositoryCredentialRef());
    return node;
  }

  /** 설계 364·665행: name·type·설정 revision·설정·자격증명 참조. */
  private ObjectNode targetSnapshot(Target target) {
    ObjectNode node = mapper.createObjectNode();
    node.put("name", target.name());
    node.put("environment_type", target.environmentType());
    node.set("config", target.config());
    node.put("config_revision", target.configRevision());
    node.put("credential_ref", target.credentialRef());
    node.put("credential_version", target.credentialVersion());
    return node;
  }

  /**
   * 설계 339행: 비밀값 없는 공통 입력과 {@code hash_format_version}.
   *
   * <p>지금은 {@code strategy} 하나만 받고 값은 {@code recreate} 만 허용해요. 다른 키나 {@code hash_format_version} 을
   * 사용자가 보내면 400 이에요 — 사용자가 해시 형식 번호를 바꾸지 못하게 하려는 거예요.
   */
  ObjectNode commonInput(JsonNode input) {
    String strategy = STRATEGY_RECREATE;
    if (input != null && !input.isNull()) {
      if (!input.isObject()) {
        throw fail(ErrorCode.VALIDATION_FAILED);
      }
      for (Map.Entry<String, JsonNode> entry : input.properties()) {
        if (!"strategy".equals(entry.getKey())) {
          throw fail(ErrorCode.VALIDATION_FAILED);
        }
      }
      JsonNode requested = input.get("strategy");
      if (requested != null && !requested.isNull()) {
        if (!requested.isTextual() || !STRATEGY_RECREATE.equals(requested.asText())) {
          throw fail(ErrorCode.VALIDATION_FAILED);
        }
      }
    }
    ObjectNode node = mapper.createObjectNode();
    node.put("hash_format_version", HASH_FORMAT_VERSION);
    node.put("strategy", strategy);
    return node;
  }

  private static DaisyException fail(ErrorCode code) {
    return new DaisyException(code);
  }
}
