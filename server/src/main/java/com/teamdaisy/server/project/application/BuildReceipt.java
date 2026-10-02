package com.teamdaisy.server.project.application;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ObjectNode;
import com.teamdaisy.server.common.error.DaisyException;
import com.teamdaisy.server.common.error.ErrorCode;
import com.teamdaisy.server.history.application.EventJournal;
import com.teamdaisy.server.project.application.BuildRegistry.BuildReport;
import com.teamdaisy.server.project.application.BuildRegistry.Recorded;
import java.time.Clock;
import java.time.Instant;
import java.util.HashMap;
import java.util.Map;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import org.springframework.core.env.Environment;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;

/**
 * Jenkins CI 빌드 결과를 받아 저장하고 {@code build.received} 를 남겨요 (#35, 10/2 승환님 조건).
 *
 * <p>Jenkins 가 보낸 {@code project_id} 만 믿지 않아요. {@code source} 가 우리 Jenkins 인스턴스이고, Job 이 서버 설정의
 * Job→프로젝트 매핑에 있고, 그 프로젝트가 {@code project_id} 와 같아야 저장해요. 저장과 이벤트는 한 트랜잭션이에요.
 */
@Component
public class BuildReceipt {
  private static final Pattern BUILD_ID = Pattern.compile("(.+)#([0-9]{1,18})");
  private static final String EVENT = "build.received";

  private final BuildRegistry registry;
  private final EventJournal journal;
  private final Environment env;
  private final ObjectMapper mapper;
  private final Clock clock;

  public BuildReceipt(
      BuildRegistry registry,
      EventJournal journal,
      Environment env,
      ObjectMapper mapper,
      Clock clock) {
    this.registry = registry;
    this.journal = journal;
    this.env = env;
    this.mapper = mapper;
    this.clock = clock;
  }

  @Transactional
  public Recorded receive(BuildReport input) {
    BuildReport report = BuildRegistry.validate(input);
    requireTrusted(report);
    Recorded recorded = registry.record(report);
    if (recorded.statusChanged()) {
      ObjectNode payload =
          mapper
              .createObjectNode()
              .put("source_version_id", recorded.sourceVersionId())
              .put("commit_sha", report.commitSha())
              .put("status", report.status());
      journal.appendProject(
          report.projectId(),
          new EventJournal.ProjectInput(
              report.source(),
              report.externalBuildId() + ":" + report.status(),
              null,
              recorded.sourceVersionId(),
              EVENT,
              payload,
              occurredAt(report)));
    }
    return recorded;
  }

  /** 우리 Jenkins 인스턴스와 설정된 Job→프로젝트 매핑으로 보낸 쪽을 확인해요. */
  void requireTrusted(BuildReport report) {
    String expectedSource =
        "jenkins:" + env.getProperty("daisy.jenkins.instance-id", "proposal-jenkins");
    if (!expectedSource.equals(report.source())) {
      throw new DaisyException(ErrorCode.FORBIDDEN);
    }
    Matcher matcher = BUILD_ID.matcher(report.externalBuildId());
    if (!matcher.matches()) {
      throw new DaisyException(ErrorCode.VALIDATION_FAILED);
    }
    String project =
        jobProjects(env.getProperty("daisy.jenkins.ci-projects", "")).get(matcher.group(1));
    if (project == null || !project.equals(report.projectId())) {
      throw new DaisyException(ErrorCode.FORBIDDEN);
    }
  }

  /** {@code Job=프로젝트ID} 를 쉼표로 이은 설정을 읽어요. 형식이 틀린 항목은 무시해서 그 Job 은 막혀요. */
  static Map<String, String> jobProjects(String value) {
    Map<String, String> map = new HashMap<>();
    if (value == null) {
      return map;
    }
    for (String entry : value.split(",")) {
      int eq = entry.indexOf('=');
      if (eq < 0) {
        continue;
      }
      String job = entry.substring(0, eq).trim();
      String project = entry.substring(eq + 1).trim();
      if (!job.isEmpty() && !project.isEmpty()) {
        map.put(job, project);
      }
    }
    return map;
  }

  private Instant occurredAt(BuildReport report) {
    if (report.finishedAt() != null) {
      return report.finishedAt();
    }
    return report.startedAt() != null ? report.startedAt() : clock.instant();
  }
}
