package com.teamdaisy.server.project.domain;

import java.util.List;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;

public interface TargetRepository extends JpaRepository<Target, String> {

  /**
   * 프로젝트에 연결된 배포 대상을 돌려줘요. 보관된 대상은 빼요.
   *
   * <p>정렬을 {@code (environment_type, name)} 으로 고정한 것은 화면에서 환경 순서가 요청마다 바뀌지 않게 하려는 거예요.
   *
   * <p>{@code projectId} 로만 걸러요. 호출 전에 접근 판정을 하더라도 질의 자체가 프로젝트 경계를 넘지 않아야 다른 프로젝트의 대상이 섞이지 않아요.
   */
  @Query(
      """
      select t from Target t
      where t.projectId = :projectId and t.archivedAt is null
      order by t.environmentType asc, t.name asc
      """)
  List<Target> findActiveByProject(String projectId);
}
