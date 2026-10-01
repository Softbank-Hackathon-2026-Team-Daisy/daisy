package com.teamdaisy.server.project.domain;

import java.util.Optional;
import org.springframework.data.jpa.repository.JpaRepository;

public interface ProjectMemberRepository extends JpaRepository<ProjectMember, ProjectMemberId> {
  Optional<ProjectMember> findByIdProjectIdAndIdAccountId(String projectId, String accountId);
}
