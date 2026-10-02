package com.teamdaisy.server.project.web;

import com.teamdaisy.server.common.error.DaisyException;
import com.teamdaisy.server.common.error.ErrorCode;
import java.nio.charset.StandardCharsets;
import java.time.Instant;
import java.time.format.DateTimeParseException;
import java.util.Base64;

/**
 * 빌드 목록 커서예요. {@code (received_at, id)} 한 쌍을 담아요.
 *
 * <p>base64url 로 감싸는 것은 <b>소비자가 파싱하지 못하게</b> 하려는 거예요. 안을 들여다보고 직접 만들기 시작하면 정렬 키를 바꿀 수 없어요. 암호화가 아니라
 * 불투명하게 만드는 것일 뿐이라 비밀값을 넣지 않아요.
 *
 * @param receivedAt 마지막으로 돌려준 행의 수신 시각
 * @param id 같은 시각의 행을 가르는 동반 키
 */
public record BuildCursor(Instant receivedAt, String id) {
  private static final String SEPARATOR = "\u001f"; // ID 에 나올 수 없는 문자예요.

  public String encode() {
    String raw = receivedAt.toString() + SEPARATOR + id;
    return Base64.getUrlEncoder()
        .withoutPadding()
        .encodeToString(raw.getBytes(StandardCharsets.UTF_8));
  }

  /** 해독할 수 없는 커서는 400 이에요. 조용히 첫 페이지로 돌려보내면 사용자는 목록이 되감긴 것을 모르고 지나쳐요. */
  public static BuildCursor decode(String encoded) {
    try {
      String raw = new String(Base64.getUrlDecoder().decode(encoded), StandardCharsets.UTF_8);
      int at = raw.indexOf(SEPARATOR);
      if (at <= 0 || at == raw.length() - 1) {
        throw new DaisyException(ErrorCode.VALIDATION_FAILED);
      }
      return new BuildCursor(Instant.parse(raw.substring(0, at)), raw.substring(at + 1));
    } catch (IllegalArgumentException | DateTimeParseException e) {
      throw new DaisyException(ErrorCode.VALIDATION_FAILED);
    }
  }
}
