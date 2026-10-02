package com.teamdaisy.server.project.application;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ObjectNode;
import com.teamdaisy.server.common.error.DaisyException;
import com.teamdaisy.server.common.error.ErrorCode;
import com.teamdaisy.server.common.json.CanonicalJson;
import com.teamdaisy.server.history.application.EventJournal;
import com.teamdaisy.server.project.application.BuildRegistry.BuildReport;
import com.teamdaisy.server.project.application.BuildRegistry.Recorded;
import com.teamdaisy.server.project.domain.ImageRefs;
import java.sql.Connection;
import java.sql.SQLException;
import java.time.Clock;
import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.BrokenBarrierException;
import java.util.concurrent.CyclicBarrier;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.TimeoutException;
import javax.sql.DataSource;
import org.flywaydb.core.Flyway;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.condition.EnabledIfEnvironmentVariable;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.core.namedparam.NamedParameterJdbcTemplate;
import org.springframework.jdbc.datasource.AbstractDataSource;
import org.springframework.jdbc.datasource.DataSourceTransactionManager;
import org.springframework.jdbc.datasource.DriverManagerDataSource;
import org.springframework.mock.env.MockEnvironment;
import org.springframework.transaction.support.TransactionTemplate;

/**
 * 빌드 저장을 실제 PostgreSQL 에서 고정해요 (server/SPEC.md 「빌드 결과 저장」 R1~R5·R7~R9).
 *
 * <p>수신부처럼 호출을 트랜잭션 안에서 해요. 테스트마다 새 스키마를 쓰고 지워요.
 */
@EnabledIfEnvironmentVariable(named = "DAISY_TEST_DB_URL", matches = ".+")
class BuildRegistryPostgresTest {
  private static final ObjectMapper MAPPER = new ObjectMapper();
  private static final String COMMIT = "a".repeat(40);
  private static final Instant DONE = Instant.parse("2026-10-02T01:00:00Z");

  private final String schema = "daisy_b_" + UUID.randomUUID().toString().replace("-", "");
  private DataSource base;
  private JdbcTemplate jdbc;
  private TransactionTemplate tx;
  private BuildRegistry registry;

  @BeforeEach
  void setup() {
    base =
        new DriverManagerDataSource(
            System.getenv("DAISY_TEST_DB_URL"),
            System.getenv("DAISY_TEST_DB_USER"),
            System.getenv("DAISY_TEST_DB_PASSWORD"));
    new JdbcTemplate(base).execute("CREATE SCHEMA " + schema);
    DataSource scoped =
        new AbstractDataSource() {
          @Override
          public Connection getConnection() throws SQLException {
            return scope(base.getConnection());
          }

          @Override
          public Connection getConnection(String user, String password) throws SQLException {
            return scope(base.getConnection(user, password));
          }

          private Connection scope(Connection connection) throws SQLException {
            connection.setSchema(schema);
            try (var statement = connection.createStatement()) {
              statement.execute("SET lock_timeout='10s'");
            }
            return connection;
          }
        };
    Flyway.configure()
        .dataSource(scoped)
        .defaultSchema(schema)
        .locations("classpath:db/migration")
        .load()
        .migrate();
    jdbc = new JdbcTemplate(scoped);
    tx = new TransactionTemplate(new DataSourceTransactionManager(scoped));
    registry = new BuildRegistry(new NamedParameterJdbcTemplate(jdbc), MAPPER);
    jdbc.update(
        "insert into account(id,username,password_hash,display_name,role)"
            + " values('acct_1','fixture','TEST-ONLY-HASH','Fixture','owner')");
    for (String project : List.of("prj_1", "prj_2", "prj_old")) {
      jdbc.update(
          "insert into project(id,name,repository_id,repository_url,default_branch,created_by)"
              + " values(?,?,?,'https://example.test/repo','main','acct_1')",
          project,
          project,
          "repo-" + project);
    }
    jdbc.update("update project set archived_at = now() where id = 'prj_old'");
  }

  @AfterEach
  void cleanup() {
    new JdbcTemplate(base).execute("DROP SCHEMA IF EXISTS " + schema + " CASCADE");
  }

  private static ObjectNode images(String tag) {
    ObjectNode images = MAPPER.createObjectNode();
    images.putObject("web").put("image_ref", "ghcr.io/x/web:" + tag).put("commit_sha", COMMIT);
    return images;
  }

  private static BuildReport report(String project, String status, ObjectNode images) {
    boolean done = "succeeded".equals(status) || "failed".equals(status);
    return new BuildReport(
        project,
        "jenkins-1",
        "daisy-ci#7",
        COMMIT,
        "main",
        status,
        images,
        "https://jenkins.test/job/daisy-ci/7/",
        DONE.minusSeconds(60),
        done ? DONE : null,
        null);
  }

  private Recorded record(BuildReport report) {
    return tx.execute(status -> registry.record(report));
  }

  private void assertCode(Runnable call, ErrorCode code) {
    assertThatThrownBy(call::run)
        .isInstanceOf(DaisyException.class)
        .extracting(exception -> ((DaisyException) exception).errorCode())
        .isEqualTo(code);
  }

  private Map<String, Object> row() {
    return jdbc.queryForMap(
        "select id, status, image_refs::text as images, received_at from source_version");
  }

  @Test
  @DisplayName("R1~R4·R8: 진행 → 성공 한 행, 재수신 무변경, 역행 무시, 종료 결과 변경 409")
  void lifecycle() throws Exception {
    Recorded running = record(report("prj_1", "running", null));
    Object receivedAt = row().get("received_at");
    Recorded succeeded = record(report("prj_1", "succeeded", images(COMMIT)));

    assertThat(running.changed()).isTrue();
    assertThat(succeeded).isEqualTo(new Recorded(running.sourceVersionId(), true, true));
    assertThat(jdbc.queryForObject("select count(*) from source_version", Integer.class))
        .isEqualTo(1);

    // 배포 생성·A-06 이 쓰는 조건: 성공 + 계약 모양 이미지. 받은 시각(A-06 커서)은 처음 그대로
    Map<String, Object> row = row();
    assertThat(row.get("status")).isEqualTo("succeeded");
    assertThat(ImageRefs.valid(MAPPER.readTree((String) row.get("images")), COMMIT)).isTrue();
    assertThat(row.get("received_at")).isEqualTo(receivedAt);

    assertThat(record(report("prj_1", "succeeded", images(COMMIT))).changed()).isFalse();
    assertThat(record(report("prj_1", "running", null)).changed()).isFalse();
    assertThat(row().get("status")).isEqualTo("succeeded");

    assertCode(() -> record(report("prj_1", "failed", null)), ErrorCode.STATE_CONFLICT);
    assertCode(
        () -> record(report("prj_1", "succeeded", images("other"))), ErrorCode.STATE_CONFLICT);
    assertThat(row().get("status")).isEqualTo("succeeded");
  }

  @Test
  @DisplayName("R5·R7: 같은 키 다른 프로젝트 409, 없는·보관된 프로젝트 404")
  void identityAndProject() {
    record(report("prj_1", "running", null));
    assertCode(() -> record(report("prj_2", "running", null)), ErrorCode.STATE_CONFLICT);
    assertCode(() -> record(report("prj_none", "running", null)), ErrorCode.NOT_FOUND);
    assertCode(() -> record(report("prj_old", "running", null)), ErrorCode.NOT_FOUND);
    assertThat(jdbc.queryForObject("select count(*) from source_version", Integer.class))
        .isEqualTo(1);
  }

  @Test
  @DisplayName("R9: 같은 키가 동시에 와도 한 행이고, 바뀌었다고 답하는 건 하나예요")
  void concurrentSameKey() throws Exception {
    CyclicBarrier start = new CyclicBarrier(2);
    ExecutorService pool = Executors.newFixedThreadPool(2);
    try {
      List<Future<Recorded>> calls =
          List.of(
              pool.submit(
                  () -> {
                    start.await(5, TimeUnit.SECONDS);
                    return record(report("prj_1", "succeeded", images(COMMIT)));
                  }),
              pool.submit(
                  () -> {
                    start.await(5, TimeUnit.SECONDS);
                    return record(report("prj_1", "succeeded", images(COMMIT)));
                  }));
      Recorded first = calls.get(0).get(20, TimeUnit.SECONDS);
      Recorded second = calls.get(1).get(20, TimeUnit.SECONDS);

      assertThat(first.sourceVersionId()).isEqualTo(second.sourceVersionId());
      assertThat(List.of(first.changed(), second.changed())).containsExactlyInAnyOrder(true, false);
      assertThat(jdbc.queryForObject("select count(*) from source_version", Integer.class))
          .isEqualTo(1);
    } finally {
      pool.shutdownNow();
    }
  }

  @Test
  @DisplayName("#72 리뷰: 같은 프로젝트의 다른 빌드 둘이 동시에 수신돼도 교착 없이 둘 다 저장 · 이벤트 기록돼요")
  void concurrentReceiptsSameProject() throws Exception {
    // 저장 직후 두 트랜잭션이 서로를 기다리게 해서 승환님 재현(두 INSERT 를 끝낸 뒤 이벤트 기록)을 만들어요.
    // 프로젝트를 먼저 잠그면 뒤 요청은 잠금에서 기다려서 여기 오지 못해요. 장벽은 시간 초과로 풀리고 순서대로 끝나요.
    CyclicBarrier afterRecord = new CyclicBarrier(2);
    NamedParameterJdbcTemplate named = new NamedParameterJdbcTemplate(jdbc);
    BuildRegistry racing =
        new BuildRegistry(named, MAPPER) {
          @Override
          public Recorded record(BuildReport input) {
            Recorded recorded = super.record(input);
            try {
              afterRecord.await(3, TimeUnit.SECONDS);
            } catch (BrokenBarrierException | TimeoutException ignored) {
              // 다른 쪽이 잠금에서 기다리는 중이에요. 그대로 진행해요
            } catch (InterruptedException interrupted) {
              Thread.currentThread().interrupt();
            }
            return recorded;
          }
        };
    // 이벤트 기록은 시각(Instant)을 직렬화해서 시간 모듈이 있는 매퍼를 써요 (EventJournalTest 와 같아요)
    ObjectMapper events = new ObjectMapper().findAndRegisterModules();
    BuildReceipt receipt =
        new BuildReceipt(
            racing,
            new EventJournal(named, events, new CanonicalJson(events)),
            new MockEnvironment()
                .withProperty("daisy.jenkins.instance-id", "unibloom-onprem")
                .withProperty("daisy.jenkins.ci-projects", "daisy-ci=prj_1"),
            events,
            Clock.systemUTC());
    CyclicBarrier start = new CyclicBarrier(2);
    ExecutorService pool = Executors.newFixedThreadPool(2);
    try {
      List<Future<Recorded>> calls = new ArrayList<>();
      for (String build : List.of("daisy-ci#1", "daisy-ci#2")) {
        calls.add(
            pool.submit(
                () -> {
                  start.await(5, TimeUnit.SECONDS);
                  return tx.execute(status -> receipt.receive(ciReport(build)));
                }));
      }
      for (Future<Recorded> call : calls) {
        assertThat(call.get(30, TimeUnit.SECONDS).changed()).isTrue();
      }
      assertThat(jdbc.queryForObject("select count(*) from source_version", Integer.class))
          .isEqualTo(2);
      assertThat(
              jdbc.queryForObject(
                  "select count(*) from project_event where event_type = 'build.received'",
                  Integer.class))
          .isEqualTo(2);
    } finally {
      pool.shutdownNow();
    }
  }

  private static BuildReport ciReport(String build) {
    return new BuildReport(
        "prj_1",
        "jenkins:unibloom-onprem",
        build,
        COMMIT,
        "main",
        "running",
        null,
        "https://jenkins.test/job/daisy-ci/1/",
        DONE.minusSeconds(60),
        null,
        null);
  }
}
