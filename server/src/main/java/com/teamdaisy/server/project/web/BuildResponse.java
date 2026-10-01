package com.teamdaisy.server.project.web;

import com.fasterxml.jackson.databind.JsonNode;
import com.teamdaisy.server.project.domain.SourceVersion;
import java.time.Instant;
import java.util.ArrayList;
import java.util.Iterator;
import java.util.List;
import java.util.Map;

/**
 * 빌드 목록 응답이에요 (A-06). 소비자 모델은 {@code ios/SPEC.md} §6-7 의 {@code Build} 예요.
 *
 * <p>DB enum 을 그대로 내보내지 않아요. 승환 S1 의 *"나머지 상태도 기존 소비자 enum 을 대조하고, DB enum 을 API 에 그대로 노출하지 않는다"* 를
 * 따라요.
 */
public record BuildResponse(
    String sourceVersionId,
    String commit,
    String branch,
    Pipeline pipeline,
    String image,
    String imageDigest,
    List<ServiceImage> images,
    List<Object> deployedTo,
    Instant startedAt,
    Instant finishedAt,
    Instant receivedAt,
    String errorSummary) {

  public record Pipeline(String status, String runUrl) {}

  public record ServiceImage(String service, String imageRef, String imageDigest) {}

  /** `image_refs` 안에서 이 두 키를 찾아요. 모양이 확정되면 여기만 바뀌어요. */
  private static final String KEY_REF = "image_ref";

  private static final String KEY_DIGEST = "image_digest";

  /**
   * DB 상태를 소비자 enum 으로 바꿔요.
   *
   * <p>DB 는 네 값(`pending`·`running`·`succeeded`·`failed`)인데 소비자 계약은 세
   * 값(`running`·`success`·`failed`)이에요. {@code pending} 에 대응이 없어서 {@code queued} 를 내보내요. <b>{@code
   * running} 으로 보내지 않아요</b> — 시작하지 않은 것을 진행 중으로 표시하면 없는 사실을 만드는 거예요. 소비자 계약에 없는 값이라 웹·앱에 알려야 해요.
   */
  static String pipelineStatus(String dbStatus) {
    if (dbStatus == null) {
      return null;
    }
    return switch (dbStatus) {
      case "succeeded" -> "success";
      case "pending" -> "queued";
      case "running", "failed" -> dbStatus;
      // 설계 밖의 값이 들어오면 꾸미지 않고 그대로 내보내요. 소비자가 모르는 값을 보는 게, 아는 값으로 둔갑한 것보다 안전해요.
      default -> dbStatus;
    };
  }

  /**
   * `image_refs` 를 평탄화해요.
   *
   * <p>서비스가 하나면 scalar 로, 둘 이상이면 scalar 를 null 로 두고 배열로 내보내요. 승환 S5 의 *"임의의 첫 서비스나 서로 다른 digest 를
   * 합친 hash 를 Docker digest 처럼 제공하지 않는다"* 를 따라요.
   *
   * <p>모양이 가정과 다르면 <b>오류를 내지 않고 비워요.</b> 빌드 목록 조회가 통째로 깨지는 것보다 그 필드만 비는 쪽이 나아요.
   */
  static Images flatten(JsonNode imageRefs) {
    if (imageRefs == null || !imageRefs.isObject() || imageRefs.isEmpty()) {
      return Images.empty();
    }
    List<ServiceImage> services = new ArrayList<>();
    Iterator<Map.Entry<String, JsonNode>> fields = imageRefs.fields();
    while (fields.hasNext()) {
      Map.Entry<String, JsonNode> entry = fields.next();
      JsonNode value = entry.getValue();
      if (value == null || !value.isObject()) {
        // 가정한 모양이 아니에요. 추측해서 채우지 않아요.
        return Images.empty();
      }
      services.add(new ServiceImage(entry.getKey(), text(value, KEY_REF), text(value, KEY_DIGEST)));
    }
    if (services.size() == 1) {
      ServiceImage only = services.get(0);
      return new Images(only.imageRef(), only.imageDigest(), null);
    }
    return new Images(null, null, List.copyOf(services));
  }

  private static String text(JsonNode node, String field) {
    JsonNode value = node.get(field);
    return value == null || !value.isTextual() ? null : value.asText();
  }

  /** 평탄화 결과예요. scalar 와 배열 중 한쪽만 채워져요. */
  record Images(String image, String imageDigest, List<ServiceImage> images) {
    static Images empty() {
      return new Images(null, null, null);
    }
  }

  public static BuildResponse of(SourceVersion version) {
    Images images = flatten(version.imageRefs());
    return new BuildResponse(
        version.id(),
        version.commitSha(),
        version.branch(),
        new Pipeline(pipelineStatus(version.status()), version.runUrl()),
        images.image(),
        images.imageDigest(),
        images.images(),
        // deployment 모듈 소유라 읽지 않아요. 조회 서비스 계약이 생기면 채워요 (A-02 의 current 와 같은 이유).
        null,
        version.startedAt(),
        version.finishedAt(),
        version.receivedAt(),
        version.errorSummary());
  }
}
