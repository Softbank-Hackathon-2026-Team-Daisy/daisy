package com.teamdaisy.server.project.domain;

import com.fasterxml.jackson.databind.JsonNode;
import java.util.Map;
import java.util.regex.Pattern;

/**
 * 빌드 이미지 목록 {@code image_refs} 의 계약 모양이에요. 빌드 저장과 배포 생성이 같은 규칙을 써요.
 *
 * <p>모양은 {@code {service: {image_ref, digest?, commit_sha}}} 예요. 모든 서비스의 {@code commit_sha} 가 빌드
 * commit 과 같아야 해요. digest 는 미확인이면 없어도 되지만, 있으면 {@code sha256:} 과 64자리 hex 여야 해요.
 */
public final class ImageRefs {
  private static final Pattern DIGEST = Pattern.compile("sha256:[0-9a-f]{64}");

  private ImageRefs() {}

  public static boolean valid(JsonNode images, String commit) {
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
}
