package com.teamdaisy.server.project.domain;

import java.time.Instant;
import java.util.List;
import org.springframework.data.domain.Limit;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;

public interface SourceVersionRepository extends JpaRepository<SourceVersion, String> {

  /**
   * 프로젝트의 빌드를 최근 순으로 돌려줘요. 첫 페이지예요.
   *
   * <p>정렬에 {@code id} 를 동반 키로 넣은 것은 {@code received_at} 이 같은 행이 있을 수 있어서예요. 단일 키로 커서를 만들면 같은 시각의 행을
   * 건너뛰거나 두 번 보여 줘요. 설계 5.5 의 {@code INDEX(project_id, received_at DESC, id)} 가 이 정렬용이에요.
   */
  @Query(
      """
      select v from SourceVersion v
      where v.projectId = :projectId
      order by v.receivedAt desc, v.id desc
      """)
  List<SourceVersion> findFirstPage(String projectId, Limit limit);

  /**
   * 커서 다음 페이지예요. {@code (received_at, id)} 를 묶어 비교해요.
   *
   * <p>{@code receivedAt < :at} 과 {@code (receivedAt = :at and id < :id)} 를 함께 보는 이유는 같은 시각의 행이 여러
   * 개일 때 그 안에서도 이어서 읽어야 하기 때문이에요.
   */
  @Query(
      """
      select v from SourceVersion v
      where v.projectId = :projectId
        and (v.receivedAt < :at or (v.receivedAt = :at and v.id < :id))
      order by v.receivedAt desc, v.id desc
      """)
  List<SourceVersion> findAfterCursor(String projectId, Instant at, String id, Limit limit);
}
