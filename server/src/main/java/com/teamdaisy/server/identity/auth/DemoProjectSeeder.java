package com.teamdaisy.server.identity.auth;

import com.teamdaisy.server.identity.domain.AccountRepository;
import com.teamdaisy.server.project.domain.Project;
import com.teamdaisy.server.project.domain.ProjectMember;
import com.teamdaisy.server.project.domain.ProjectMemberRepository;
import com.teamdaisy.server.project.domain.ProjectRepository;
import java.time.Clock;
import java.time.Instant;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.ApplicationRunner;
import org.springframework.core.annotation.Order;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;

/**
 * 데모 프로젝트를 심어요. 웹·앱이 붙어 볼 대상이 하나는 있어야 해서예요.
 *
 * <p>데모 계정이 없으면 아무것도 하지 않아요. 계정 시딩(@Order(50)) 뒤에 돌아야 해서 @Order(100) 이에요. ApplicationRunner
 * 는 @Order 가 없으면 가장 마지막이라, 두 러너 모두 순서를 명시해요. 실제 저장소 연결 절차가 정해지면 이 시딩은 걷어내요.
 */
@Component
@Order(100)
public class DemoProjectSeeder implements ApplicationRunner {
  private static final Logger LOG = LoggerFactory.getLogger(DemoProjectSeeder.class);
  private static final String PROJECT_ID = "prj_demo_monolith";

  private final ProjectRepository projects;
  private final ProjectMemberRepository members;
  private final AccountRepository accounts;
  private final Clock clock;

  public DemoProjectSeeder(
      ProjectRepository projects,
      ProjectMemberRepository members,
      AccountRepository accounts,
      Clock clock) {
    this.projects = projects;
    this.members = members;
    this.accounts = accounts;
    this.clock = clock;
  }

  @Override
  @Transactional
  public void run(ApplicationArguments args) {
    if (accounts.count() == 0 || projects.existsById(PROJECT_ID)) {
      return;
    }
    Instant now = clock.instant();
    String owner =
        accounts.findAll().stream()
            .filter(account -> !AuthPrincipal.VIEWER.equals(account.role()))
            .map(account -> account.id())
            .findFirst()
            .orElse(null);
    if (owner == null) {
      return;
    }
    projects.save(
        Project.connect(
            PROJECT_ID,
            "sample-monolith",
            "Softbank-Hackathon-2026-Team-Daisy/sample-monolith",
            "https://github.com/Softbank-Hackathon-2026-Team-Daisy/sample-monolith",
            "main",
            "deploy.yaml",
            owner,
            now));
    // 데모 계정 전원에게 접근 권한을 줘요. 심사위원 계정도 조회는 돼야 해요.
    accounts
        .findAll()
        .forEach(
            account -> members.save(ProjectMember.grant(PROJECT_ID, account.id(), owner, now)));
    LOG.info("데모 프로젝트를 만들었어요. projectId={}", PROJECT_ID);
  }
}
