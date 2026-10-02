package com.teamdaisy.server.project.web;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import com.fasterxml.jackson.databind.node.JsonNodeFactory;
import com.fasterxml.jackson.databind.node.ObjectNode;
import com.teamdaisy.server.common.error.DaisyException;
import com.teamdaisy.server.common.error.ErrorCode;
import com.teamdaisy.server.deployment.domain.Deployment;
import java.time.Instant;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

/**
 * 빌드 응답 변환과 커서를 고정해요 (A-06).
 *
 * <p>DB enum 을 소비자 enum 으로 바꾸는 규칙과 {@code image_refs} 평탄화가 핵심이에요. 둘 다 없는 사실을 만들지 않는 것이 조건이에요.
 */
class BuildResponseTest {

  private static ObjectNode service(String ref, String digest) {
    ObjectNode node = JsonNodeFactory.instance.objectNode();
    if (ref != null) {
      node.put("image_ref", ref);
    }
    if (digest != null) {
      node.put("digest", digest);
    }
    return node;
  }

  @Test
  @DisplayName("succeeded 는 success 로 바꿔요")
  void succeededBecomesSuccess() {
    assertThat(BuildResponse.pipelineStatus("succeeded")).isEqualTo("success");
  }

  @Test
  @DisplayName("pending 을 running 으로 보내지 않아요")
  void pendingIsNotRunning() {
    // 시작하지 않은 것을 진행 중으로 표시하면 없는 사실을 만드는 거예요.
    assertThat(BuildResponse.pipelineStatus("pending")).isEqualTo("queued");
    assertThat(BuildResponse.pipelineStatus("pending")).isNotEqualTo("running");
  }

  @Test
  @DisplayName("running·failed 는 그대로예요")
  void passThroughStates() {
    assertThat(BuildResponse.pipelineStatus("running")).isEqualTo("running");
    assertThat(BuildResponse.pipelineStatus("failed")).isEqualTo("failed");
  }

  @Test
  @DisplayName("모르는 값을 아는 값으로 둔갑시키지 않아요")
  void unknownStateIsNotDisguised() {
    assertThat(BuildResponse.pipelineStatus("cancelled")).isEqualTo("cancelled");
    assertThat(BuildResponse.pipelineStatus(null)).isNull();
  }

  @Test
  void executionImageShapeKeepsDigestInPublicResponse() {
    var nodes = JsonNodeFactory.instance;
    String commit = "a".repeat(40);
    String digest = "sha256:" + "b".repeat(64);
    var deployment =
        Deployment.create(
            "dep_1",
            "prj_1",
            "acc_1",
            commit,
            nodes.objectNode(),
            nodes.objectNode().put("hash_format_version", 1),
            digest,
            Instant.now());
    var refs = nodes.objectNode();
    refs.set("app", service("docker.io/team/app:" + commit, digest).put("commit_sha", commit));
    deployment.bindSource("src_1", commit, refs, digest);
    assertThat(BuildResponse.flatten(deployment.imageRefs()).imageDigest()).isEqualTo(digest);
  }

  @Test
  @DisplayName("서비스가 하나면 scalar 로 내보내요")
  void singleServiceIsScalar() {
    ObjectNode refs = JsonNodeFactory.instance.objectNode();
    refs.set("app", service("ghcr.io/org/app:2311c0b", "sha256:aaa"));

    BuildResponse.Images images = BuildResponse.flatten(refs);

    assertThat(images.image()).isEqualTo("ghcr.io/org/app:2311c0b");
    assertThat(images.imageDigest()).isEqualTo("sha256:aaa");
    assertThat(images.images()).isNull();
  }

  @Test
  @DisplayName("서비스가 둘이면 scalar 를 비우고 배열로 내보내요")
  void multiServiceIsArray() {
    ObjectNode refs = JsonNodeFactory.instance.objectNode();
    refs.set("api", service("ghcr.io/org/api:2311c0b", "sha256:aaa"));
    refs.set("web", service("ghcr.io/org/web:2311c0b", "sha256:bbb"));

    BuildResponse.Images images = BuildResponse.flatten(refs);

    // 임의의 첫 서비스를 고르거나 digest 를 합쳐 하나로 만들지 않아요 (승환 S5).
    assertThat(images.image()).isNull();
    assertThat(images.imageDigest()).isNull();
    assertThat(images.images()).hasSize(2);
    assertThat(images.images())
        .extracting(BuildResponse.ServiceImage::service)
        .containsExactly("api", "web");
  }

  @Test
  @DisplayName("모양이 가정과 다르면 오류 없이 비워요")
  void unexpectedShapeIsEmptyNotError() {
    ObjectNode wrong = JsonNodeFactory.instance.objectNode();
    wrong.put("app", "ghcr.io/org/app:2311c0b"); // 객체가 아니라 문자열이에요.

    BuildResponse.Images images = BuildResponse.flatten(wrong);

    // 빌드 목록 조회가 통째로 깨지는 것보다 그 필드만 비는 쪽이 나아요.
    assertThat(images.image()).isNull();
    assertThat(images.images()).isNull();
  }

  @Test
  @DisplayName("비어 있거나 null 인 image_refs 도 오류가 아니에요")
  void emptyRefsAreEmpty() {
    assertThat(BuildResponse.flatten(null).image()).isNull();
    assertThat(BuildResponse.flatten(JsonNodeFactory.instance.objectNode()).image()).isNull();
  }

  @Test
  @DisplayName("ref 나 digest 가 없어도 서비스 이름은 살려요")
  void missingFieldsKeepServiceName() {
    ObjectNode refs = JsonNodeFactory.instance.objectNode();
    refs.set("api", service("ghcr.io/org/api:1", null));
    refs.set("web", service(null, "sha256:bbb"));

    BuildResponse.Images images = BuildResponse.flatten(refs);

    assertThat(images.images()).hasSize(2);
    assertThat(images.images().get(0).imageDigest()).isNull();
    assertThat(images.images().get(1).imageRef()).isNull();
  }

  @Test
  @DisplayName("커서는 왕복해도 같은 값이에요")
  void cursorRoundTrips() {
    BuildCursor original = new BuildCursor(Instant.parse("2026-10-01T12:34:56.789Z"), "src_42");

    BuildCursor decoded = BuildCursor.decode(original.encode());

    assertThat(decoded).isEqualTo(original);
  }

  @Test
  @DisplayName("커서에 구분자가 없거나 깨지면 400 이에요")
  void brokenCursorIsRejected() {
    // 조용히 첫 페이지로 돌려보내면 사용자는 목록이 되감긴 것을 모르고 지나쳐요.
    for (String bad : new String[] {"", "!!!not-base64!!!", "YWJj", "AB8x"}) {
      assertThatThrownBy(() -> BuildCursor.decode(bad))
          .as("커서 %s", bad)
          .isInstanceOf(DaisyException.class)
          .extracting(exception -> ((DaisyException) exception).errorCode())
          .isEqualTo(ErrorCode.VALIDATION_FAILED);
    }
  }
}
