package com.teamdaisy.server.project.web;

import com.teamdaisy.server.project.application.DeploymentLogReader.LogRow;
import java.time.Instant;

/**
 * 로그 한 줄이에요 (A-07). 앱 {@code LogLine} 은 {@code at}·{@code message}, 웹은 {@code seq}·{@code
 * at}·{@code message} 를 받아요.
 *
 * @param seq 배포 안 순번. SSE {@code Last-Event-ID} 와 같은 값이에요
 * @param targetId 실행 전체 콘솔 로그면 null 이에요
 * @param level 저장값 그대로 소문자 debug·info·warn·error 예요 (SSE {@code log.batch} 와 같아요)
 * @param message 콘솔 묶음이면 여러 줄일 수 있어요. 비어 있으면 빈 문자열이에요
 */
public record LogLineResponse(
    long seq, Instant at, String targetId, String step, String level, String message) {

  static LogLineResponse of(LogRow row) {
    return new LogLineResponse(
        row.seq(),
        row.at(),
        row.targetId(),
        row.step(),
        row.level(),
        row.message() == null ? "" : row.message());
  }
}
