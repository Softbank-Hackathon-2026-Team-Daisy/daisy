package com.teamdaisy.server.identity.auth;

import com.fasterxml.jackson.databind.node.JsonNodeFactory;
import com.teamdaisy.server.project.domain.ProjectRepository;
import com.teamdaisy.server.project.domain.Target;
import com.teamdaisy.server.project.domain.TargetRepository;
import java.time.Clock;
import java.time.Instant;
import java.util.List;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.ApplicationRunner;
import org.springframework.core.annotation.Order;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;

/**
 * 데모 프로젝트에 배포 대상 세 개를 심어요. 현황 화면(A-02)이 빈 목록이면 앱이 붙었는지 알 수 없어서예요.
 *
 * <p>데모 시딩을 한곳에 모아 두려고 계정·프로젝트 시더와 같은 패키지에 뒀어요. 프로젝트 시딩(@Order(100)) 뒤에 돌아야 해서 @Order(150) 이에요.
 *
 * <p><b>{@code connection_state} 를 {@code unknown} 으로 심어요.</b> 실제 연결 확인을 한 적이 없는데 {@code connected}
 * 로 심으면 확인하지 않은 상태를 확인한 것처럼 보여 주게 돼요. 연결 테스트(A-10)가 생기면 그때 값이 바뀌어요.
 *
 * <p>실제 저장소·대상 등록 절차가 정해지면 이 시딩은 걷어내요.
 */
@Component
@Order(150)
public class DemoTargetSeeder implements ApplicationRunner {
  private static final Logger LOG = LoggerFactory.getLogger(DemoTargetSeeder.class);
  private static final String PROJECT_ID = "prj_demo_monolith";

  /** 환경 종류는 V1 의 {@code ck_target_env} 가 허용하는 세 값이에요. */
  private static final List<String[]> DEMO_TARGETS =
      List.of(
          new String[] {"tgt_demo_onprem", "home-lab", "onprem"},
          new String[] {"tgt_demo_aws", "aws-ap-northeast-2", "aws"},
          new String[] {"tgt_demo_gcp", "gcp-asia-northeast3", "gcp"});

  private final TargetRepository targets;
  private final ProjectRepository projects;
  private final Clock clock;

  public DemoTargetSeeder(TargetRepository targets, ProjectRepository projects, Clock clock) {
    this.targets = targets;
    this.projects = projects;
    this.clock = clock;
  }

  @Override
  @Transactional
  public void run(ApplicationArguments args) {
    if (!projects.existsById(PROJECT_ID)) {
      return;
    }
    Instant now = clock.instant();
    int created = 0;
    for (String[] spec : DEMO_TARGETS) {
      String id = spec[0];
      if (targets.existsById(id)) {
        continue;
      }
      targets.save(
          Target.create(
              id,
              PROJECT_ID,
              spec[1],
              spec[2],
              // 정규화 규칙은 인프라와 맞춘 뒤 서버가 검증·저장하기로 했어요 (#32 리뷰). 그 전까지 쓰는 임시 값이에요.
              PROJECT_ID + "/" + id,
              JsonNodeFactory.instance.objectNode(),
              // 확인한 적이 없으니 unknown 이에요.
              "unknown",
              now));
      created++;
    }
    if (created > 0) {
      LOG.info("데모 배포 대상을 만들었어요. projectId={} count={}", PROJECT_ID, created);
    }
  }
}
