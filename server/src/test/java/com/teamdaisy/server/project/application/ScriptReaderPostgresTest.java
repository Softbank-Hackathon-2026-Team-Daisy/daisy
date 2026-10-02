package com.teamdaisy.server.project.application;

import static org.assertj.core.api.Assertions.assertThat;

import com.teamdaisy.server.project.application.ScriptReader.ScriptRow;
import java.sql.Connection;
import java.sql.SQLException;
import java.sql.Timestamp;
import java.time.Instant;
import java.util.List;
import java.util.UUID;
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
import org.springframework.jdbc.datasource.DriverManagerDataSource;

/** 스크립트 목록(WR-10) 조회 SQL 을 실제 PostgreSQL 에서 고정해요 (server/SPEC.md 「스크립트 목록 WR-10」). */
@EnabledIfEnvironmentVariable(named = "DAISY_TEST_DB_URL", matches = ".+")
class ScriptReaderPostgresTest {
  private static final Instant T1 = Instant.parse("2026-10-02T01:00:00Z");
  private static final Instant T2 = Instant.parse("2026-10-02T02:00:00Z");
  private static final Instant T3 = Instant.parse("2026-10-02T03:00:00Z");

  private final String schema = "daisy_s_" + UUID.randomUUID().toString().replace("-", "");
  private DataSource base;
  private JdbcTemplate jdbc;
  private ScriptReader reader;

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
    reader = new ScriptReader(new NamedParameterJdbcTemplate(scoped));
    seed();
  }

  @AfterEach
  void cleanup() {
    new JdbcTemplate(base).execute("DROP SCHEMA IF EXISTS " + schema + " CASCADE");
  }

  private void seed() {
    jdbc.update(
        "insert into account(id,username,password_hash,display_name,role)"
            + " values('acct_1','fixture','TEST-ONLY-HASH','Fixture','owner')");
    for (String project : List.of("prj_1", "prj_2")) {
      jdbc.update(
          "insert into project(id,name,repository_id,repository_url,default_branch,created_by)"
              + " values(?,?,?,'https://example.test/repo','main','acct_1')",
          project,
          project,
          "repo-" + project);
    }
    target("tgt_a", "prj_1", "aws");
    target("tgt_b", "prj_1", "gcp");
    target("tgt_x", "prj_2", "onprem");
    for (String[] d :
        new String[][] {
          {"dep_1", "prj_1"}, {"dep_2", "prj_1"}, {"dep_3", "prj_1"}, {"dep_x", "prj_2"}
        }) {
      jdbc.update(
          "insert into deployment(id,project_id,requested_by,commit_sha,repository_snapshot,"
              + "input_snapshot,request_hash) values(?,?,'acct_1',?,'{}'::jsonb,'{}'::jsonb,'h')",
          d[0],
          d[1],
          "a".repeat(40));
    }
    // dt_a1 이 처음 검증(시도 2, 재사용 아님), dt_a2·dt_a3 가 재사용. dt_a3 가 가장 늦게 끝남
    deploymentTarget("dt_a1", "dep_1", "prj_1", "tgt_a", 2, false, T1);
    deploymentTarget("dt_a2", "dep_2", "prj_1", "tgt_a", 0, true, T2);
    deploymentTarget("dt_a3", "dep_3", "prj_1", "tgt_a", 0, true, T3);
    deploymentTarget("dt_b1", "dep_1", "prj_1", "tgt_b", 1, false, T1);
    deploymentTarget("dt_x", "dep_x", "prj_2", "tgt_x", 1, false, T1);
    script("scr_a1", "prj_1", "tgt_a", 1, "dt_a1", false);
    script("scr_a2", "prj_1", "tgt_a", 2, "dt_a1", false);
    script("scr_b1", "prj_1", "tgt_b", 1, "dt_b1", true);
    script("scr_x", "prj_2", "tgt_x", 1, "dt_x", false);
    jdbc.update(
        "update deployment_target set script_id='scr_a2' where id in ('dt_a1','dt_a2','dt_a3')");
    // scr_a2 로 만든 plan 하나 (위험 설정 2개)
    jdbc.update(
        "insert into jenkins_execution(id,deployment_id,request_id,operation,instance_id,"
            + "job_full_name,request_payload,request_hash)"
            + " values('je_1','dep_1','rq_1','prepare','inst','daisy-cd-plan','{}'::jsonb,'h')");
    jdbc.update(
        "insert into execution_target(execution_id,deployment_target_id,deployment_id)"
            + " values('je_1','dt_a1','dep_1')");
    jdbc.update(
        "insert into plan_revision(id,deployment_target_id,execution_id,project_id,target_id,"
            + "revision,source,source_plan_id,input_hash,script_id,artifact_ref,digest,summary,"
            + "resources,expires_at) values('plan_1','dt_a1','je_1','prj_1','tgt_a',1,'s','sp1','ih',"
            + "'scr_a2','ref','dg','{\"counts\":{\"create\":1,\"update\":0,\"delete\":0},"
            + "\"has_delete\":false,\"risks\":[{\"level\":\"high\",\"rule\":\"r1\",\"resource\":\"x\","
            + "\"message\":\"m\"},{\"level\":\"low\",\"rule\":\"r2\",\"resource\":\"y\",\"message\":\"m\"}]}'"
            + "::jsonb,'[]'::jsonb,now()+interval '1 hour')");
  }

  private void target(String id, String project, String type) {
    jdbc.update(
        "insert into target(id,project_id,name,environment_type,state_identity,config)"
            + " values(?,?,?,?,?,'{}')",
        id,
        project,
        id,
        type,
        "state:" + id);
  }

  private void deploymentTarget(
      String id,
      String deployment,
      String project,
      String target,
      int attempt,
      boolean reused,
      Instant finished) {
    jdbc.update(
        "insert into deployment_target(id,deployment_id,project_id,target_id,target_snapshot,"
            + "state_identity,attempt,ai_reused,started_at,finished_at)"
            + " values(?,?,?,?,'{}'::jsonb,?,?,?,?,?)",
        id,
        deployment,
        project,
        target,
        "state:" + id,
        attempt,
        reused,
        Timestamp.from(finished.minusSeconds(60)),
        Timestamp.from(finished));
  }

  private void script(
      String id, String project, String target, int version, String source, boolean unavailable) {
    jdbc.update(
        "insert into script(id,project_id,target_id,version,source,external_script_id,"
            + "source_deployment_target_id,artifact_ref,content_digest,validated_at,unavailable_at)"
            + " values(?,?,?,?,'s',?,?,'ref','sha256:x',?,?)",
        id,
        project,
        target,
        version,
        "ext-" + id,
        source,
        Timestamp.from(T1),
        unavailable ? Timestamp.from(T2) : null);
  }

  private static List<String> ids(List<ScriptRow> rows) {
    return rows.stream().map(ScriptRow::id).toList();
  }

  @Test
  @DisplayName("대상 순·버전 내림차순이고, 재사용 수·마지막 사용·plan·위험 수를 셉니다")
  void listsWithUsageAndPlan() {
    List<ScriptRow> rows = reader.list("prj_1", null);
    assertThat(ids(rows)).containsExactly("scr_a2", "scr_a1", "scr_b1");

    ScriptRow a2 = rows.get(0);
    assertThat(a2.version()).isEqualTo(2);
    assertThat(a2.environmentType()).isEqualTo("aws");
    assertThat(a2.sourceReused()).isFalse();
    assertThat(a2.sourceAttempt()).isEqualTo(2);
    assertThat(a2.reuseCount()).isEqualTo(2);
    assertThat(a2.lastUsedAt()).isEqualTo(T3);
    assertThat(a2.planCount()).isEqualTo(1);
    assertThat(a2.latestRisks()).isEqualTo(2);

    ScriptRow a1 = rows.get(1);
    assertThat(a1.reuseCount()).isZero();
    assertThat(a1.lastUsedAt()).isNull();
    assertThat(a1.planCount()).isZero();
    assertThat(a1.latestRisks()).isNull();

    assertThat(rows.get(2).unavailableAt()).isEqualTo(T2);
  }

  @Test
  @DisplayName("대상으로 거르고, 다른 프로젝트 스크립트·대상은 섞이지 않아요")
  void targetFilterAndIsolation() {
    assertThat(ids(reader.list("prj_1", "tgt_b"))).containsExactly("scr_b1");
    assertThat(ids(reader.list("prj_2", null))).containsExactly("scr_x");
    assertThat(reader.hasTarget("prj_1", "tgt_a")).isTrue();
    assertThat(reader.hasTarget("prj_1", "tgt_x")).isFalse();
  }
}
