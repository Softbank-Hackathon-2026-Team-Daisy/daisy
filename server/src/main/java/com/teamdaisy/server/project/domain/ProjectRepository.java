package com.teamdaisy.server.project.domain;

import java.util.List;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;

public interface ProjectRepository extends JpaRepository<Project, String> {
  /** 계정이 접근할 수 있는, 보관되지 않은 프로젝트예요. */
  @Query(
      """
      select p from Project p
      where p.archivedAt is null
        and exists (
          select 1 from ProjectMember m
          where m.id.projectId = p.id and m.id.accountId = :accountId and m.revokedAt is null
        )
      order by p.createdAt desc, p.id desc
      """)
  List<Project> findAccessible(String accountId);

  /** 보관되지 않은 프로젝트인지 봐요. 연결을 해제한(보관된) 프로젝트는 어디서도 열리지 않아요 (WR-13). */
  boolean existsByIdAndArchivedAtIsNull(String id);
}
