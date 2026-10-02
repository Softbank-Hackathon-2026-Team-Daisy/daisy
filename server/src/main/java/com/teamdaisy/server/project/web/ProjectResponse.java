package com.teamdaisy.server.project.web;

import com.teamdaisy.server.project.domain.Project;
import java.time.Instant;

/**
 * 프로젝트 조회 응답이에요.
 *
 * <p>DB 컬럼명을 그대로 내보내지 않아요. 저장소 식별자는 소비자 모델에 맞춰 {@code repository} 로 내보내요.
 *
 * @param lastSeq 프로젝트 채널 SSE 를 이어 받을 시작 지점이에요. 상세에서만 주고 목록에서는 null 이에요
 */
public record ProjectResponse(
    String id,
    String name,
    String repository,
    String defaultBranch,
    String repositoryUrl,
    String manifestPath,
    Instant createdAt,
    Long lastSeq) {

  /** 목록용. 상세 전용 필드는 비워서 보내요. */
  public static ProjectResponse summary(Project project) {
    return new ProjectResponse(
        project.id(),
        project.name(),
        project.repositoryId(),
        project.defaultBranch(),
        null,
        null,
        project.createdAt(),
        null);
  }

  public static ProjectResponse detail(Project project) {
    return new ProjectResponse(
        project.id(),
        project.name(),
        project.repositoryId(),
        project.defaultBranch(),
        project.repositoryUrl(),
        project.manifestPath(),
        project.createdAt(),
        project.lastEventSeq());
  }
}
