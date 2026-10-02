package com.teamdaisy.server.common.web;

import io.swagger.v3.oas.annotations.media.Schema;
import java.util.List;

/**
 * 목록 응답 봉투예요 (계약 §2 공통 응답 규칙).
 *
 * <p>단건은 리소스 객체를 그대로 돌려주고 목록만 이 봉투를 써요. 성공 응답을 공통 래퍼로 한 번 더 감싸지 않아요.
 */
public record PageResponse<T>(
    List<T> items,
    @Schema(nullable = true, description = "다음 페이지가 없으면 null이에요") String nextCursor) {
  /** 커서 없이 전부 돌려줄 때 써요. */
  public static <T> PageResponse<T> of(List<T> items) {
    return new PageResponse<>(items, null);
  }
}
