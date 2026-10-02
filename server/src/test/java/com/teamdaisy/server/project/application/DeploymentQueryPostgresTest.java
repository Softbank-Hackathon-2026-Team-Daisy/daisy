package com.teamdaisy.server.project.application;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.teamdaisy.server.common.error.DaisyException;
import com.teamdaisy.server.common.error.ErrorCode;
import com.teamdaisy.server.identity.domain.AccountRepository;
import com.teamdaisy.server.project.application.DeploymentDetailReader.DeploymentDetail;
import com.teamdaisy.server.project.application.DeploymentDetailReader.DeploymentRow;
import java.sql.Connection;
import java.sql.SQLException;
import java.sql.Timestamp;
import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import java.util.Optional;
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

/**
 * 배포 목록(A-03)·상세(A-04) 조회 SQL 을 실제 PostgreSQL 에서 고정해요 (#48 승환님 리뷰).
 *
 * <p>같은 생성 시각의 배포가 페이지 경계에 걸려도 빠지거나 겹치지 않는지, 다른 프로젝트가 섞이지 않는지 봐요. 조회 클래스는 JDBC 와 계정 이름 조회만 써서
 * Spring 컨텍스트 없이 직접 만들어요. 테스트마다 새 스키마를 쓰고 지워요.
 */
@EnabledIfEnvironmentVariable(named = "DAISY_TEST_DB_URL", matches = ".+")
class DeploymentQueryPostgresTest {
  private static final Instant T2 = Instant.parse("2026-10-02T00:02:00Z");
  private static final Instant T3 = Instant.parse("2026-10-02T00:03:00Z");
  private static final Instant T4 = Instant.parse("2026-10-02T00:04:00Z");
  private static final Instant T5 = Instant.parse("2026-10-02T00:05:00Z");

  private final String schema = "daisy_q_" + UUID.randomUUID().toString().replace("-", "");
  private DataSource base;
  private JdbcTemplate jdbc;
  private DeploymentDetailReader reader;
  private DeploymentLogReader logs;

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
    AccountRepository accounts = mock(AccountRepository.class);
    when(accounts.findById(anyString())).thenReturn(Optional.empty());
    reader =
        new DeploymentDetailReader(
            new NamedParameterJdbcTemplate(scoped), accounts, new ObjectMapper());
    logs = new DeploymentLogReader(new NamedParameterJdbcTemplate(scoped));

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
    // 최신순: dep_a(T5) → dep_c(T4) → dep_b(T4) → dep_d(T3) → dep_e(T2). dep_b·dep_c 는 시각이 같아요.
    deployment("dep_a", "prj_1", T5, "queued");
    deployment("dep_c", "prj_1", T4, "queued");
    deployment("dep_b", "prj_1", T4, "queued");
    deployment("dep_d", "prj_1", T3, "awaiting_approval");
    deployment("dep_e", "prj_1", T2, "succeeded");
    // 다른 프로젝트 배포를 같은 시각·사이 ID 로 둬서, 프로젝트 조건이 빠지면 바로 섞이게 해요.
    deployment("dep_bb", "prj_2", T4, "awaiting_approval");
  }

  @AfterEach
  void cleanup() {
    new JdbcTemplate(base).execute("DROP SCHEMA IF EXISTS " + schema + " CASCADE");
  }

  private void deployment(String id, String project, Instant at, String status) {
    jdbc.update(
        "insert into deployment(id,project_id,requested_by,commit_sha,repository_snapshot,"
            + "input_snapshot,request_hash,status,created_at)"
            + " values(?,?,'acct_1',?,'{}'::jsonb,'{}'::jsonb,'h',?,?)",
        id,
        project,
        "a".repeat(40),
        status,
        Timestamp.from(at));
  }

  private static List<String> ids(List<DeploymentDetail> page) {
    return page.stream().map(detail -> detail.deployment().id()).toList();
  }

  @Test
  @DisplayName("같은 시각 배포가 페이지 경계에 걸려도 빠지거나 겹치지 않아요")
  void cursorPagesAcrossSameCreatedAt() {
    List<String> all = ids(reader.list("prj_1", null, null, null, 100));
    assertThat(all).containsExactly("dep_a", "dep_c", "dep_b", "dep_d", "dep_e");

    List<String> walked = new ArrayList<>();
    List<List<String>> pages = new ArrayList<>();
    Instant at = null;
    String after = null;
    while (true) {
      List<DeploymentDetail> page = reader.list("prj_1", null, at, after, 2);
      pages.add(ids(page));
      walked.addAll(ids(page));
      if (page.size() < 2) {
        break;
      }
      DeploymentRow last = page.get(page.size() - 1).deployment();
      at = last.createdAt();
      after = last.id();
    }

    // 첫 페이지가 dep_c(T4) 에서 끝나고, 다음 페이지가 같은 시각의 dep_b 부터 시작해야 해요.
    assertThat(pages.get(0)).containsExactly("dep_a", "dep_c");
    assertThat(pages.get(1)).containsExactly("dep_b", "dep_d");
    assertThat(walked).isEqualTo(all);
  }

  @Test
  @DisplayName("상태로 거르고, 다른 프로젝트 배포는 목록에 섞이지 않아요")
  void stateFilterAndProjectIsolation() {
    assertThat(ids(reader.list("prj_1", "awaiting_approval", null, null, 100)))
        .containsExactly("dep_d");
    assertThat(ids(reader.list("prj_2", null, null, null, 100))).containsExactly("dep_bb");
    assertThat(ids(reader.list("prj_1", null, T4, "dep_c", 100)))
        .containsExactly("dep_b", "dep_d", "dep_e");
  }

  @Test
  @DisplayName("다른 프로젝트 배포 ID 로 상세를 읽으면 404 예요")
  void detailIsProjectScoped() {
    assertThat(reader.read("prj_2", "dep_bb").deployment().projectId()).isEqualTo("prj_2");
    assertThatThrownBy(() -> reader.read("prj_1", "dep_bb"))
        .isInstanceOf(DaisyException.class)
        .extracting(exception -> ((DaisyException) exception).errorCode())
        .isEqualTo(ErrorCode.NOT_FOUND);
  }

  /** A-07·A-04 단계용 픽스처: dep_a 에 대상 둘(실행 하나씩), dep_c 에 대상 하나. */
  private void seedLogs() {
    for (String target : List.of("tgt_a", "tgt_b")) {
      jdbc.update(
          "insert into target(id,project_id,name,environment_type,state_identity,config)"
              + " values(?,'prj_1',?,'onprem',?,'{}')",
          target,
          target,
          "state:" + target);
    }
    deploymentTarget("dt_a", "dep_a", "tgt_a");
    deploymentTarget("dt_b", "dep_a", "tgt_b");
    deploymentTarget("dt_c", "dep_c", "tgt_a");
    execution("je_1", "dep_a", "dt_a");
    execution("je_2", "dep_a", "dt_b");
    execution("je_3", "dep_c", "dt_c");
    log("dep_a", 1, "je_1", "dt_a", "log.batch", "plan", "a1");
    log("dep_a", 2, "je_1", "dt_a", "step.started", "plan", null);
    log("dep_a", 3, "je_1", null, "log.batch", null, "console je_1");
    log("dep_a", 4, "je_2", "dt_b", "log.batch", "validate", "b1");
    log("dep_a", 5, "je_1", "dt_a", "step.completed", "plan", null);
    log("dep_a", 6, "je_2", null, "log.batch", null, "console je_2");
    log("dep_a", 7, "je_1", "dt_a", "step.started", "apply", null);
    log("dep_a", 8, "je_2", "dt_b", "step.failed", "validate", null);
    log("dep_a", 9, "je_1", "dt_a", "log.batch", "apply", "a2");
    log("dep_c", 1, "je_3", "dt_c", "log.batch", null, "other deployment");
  }

  private void deploymentTarget(String id, String deployment, String target) {
    jdbc.update(
        "insert into deployment_target(id,deployment_id,project_id,target_id,target_snapshot,"
            + "state_identity) values(?,?,'prj_1',?,'{}'::jsonb,?)",
        id,
        deployment,
        target,
        "state:" + id);
  }

  private void execution(String id, String deployment, String deploymentTarget) {
    jdbc.update(
        "insert into jenkins_execution(id,deployment_id,request_id,operation,instance_id,"
            + "job_full_name,request_payload,request_hash)"
            + " values(?,?,?,'prepare','inst','daisy-cd-plan','{}'::jsonb,'h')",
        id,
        deployment,
        "rq_" + id);
    jdbc.update(
        "insert into execution_target(execution_id,deployment_target_id,deployment_id)"
            + " values(?,?,?)",
        id,
        deploymentTarget,
        deployment);
  }

  private void log(
      String deployment,
      long seq,
      String execution,
      String deploymentTarget,
      String type,
      String step,
      String message) {
    jdbc.update(
        "insert into deployment_log(deployment_id,execution_id,deployment_target_id,seq,source,"
            + "source_event_id,payload_hash,event_type,step,message,occurred_at)"
            + " values(?,?,?,?,'test',?,'h',?,?,?,?)",
        deployment,
        execution,
        deploymentTarget,
        seq,
        deployment + "-" + seq,
        type,
        step,
        message,
        Timestamp.from(T5.plusSeconds(seq)));
  }

  private static List<String> messages(List<DeploymentLogReader.LogRow> rows) {
    return rows.stream().map(DeploymentLogReader.LogRow::message).toList();
  }

  @Test
  @DisplayName("A-07: 로그 행만 오래된 것부터, tail 은 최근 것부터 자르고, 다른 배포는 섞이지 않아요")
  void logsTail() {
    seedLogs();
    assertThat(messages(logs.tail("prj_1", "dep_a", null, 100)))
        .containsExactly("a1", "console je_1", "b1", "console je_2", "a2");
    assertThat(messages(logs.tail("prj_1", "dep_a", null, 2)))
        .containsExactly("console je_2", "a2");
    assertThat(messages(logs.tail("prj_1", "dep_c", null, 100)))
        .containsExactly("other deployment");
    assertThat(logs.tail("prj_2", "dep_a", null, 100)).isEmpty();
  }

  @Test
  @DisplayName("A-07: target_id 를 주면 그 대상 행과 그 대상을 포함한 실행의 콘솔 행만 줘요")
  void logsByTarget() {
    seedLogs();
    assertThat(messages(logs.tail("prj_1", "dep_a", "tgt_a", 100)))
        .containsExactly("a1", "console je_1", "a2");
    assertThat(messages(logs.tail("prj_1", "dep_a", "tgt_b", 100)))
        .containsExactly("b1", "console je_2");
    assertThat(logs.hasTarget("prj_1", "dep_a", "tgt_a")).isTrue();
    assertThat(logs.hasTarget("prj_1", "dep_a", "tgt_none")).isFalse();
    assertThat(logs.hasTarget("prj_2", "dep_a", "tgt_a")).isFalse();
  }

  @Test
  @DisplayName("A-04: 단계는 대상마다 가장 최근 단계 이벤트에서 오고, 없으면 null 이에요")
  void stepsFromLatestEvent() {
    seedLogs();
    var targets = reader.read("prj_1", "dep_a").targets();
    assertThat(targets)
        .extracting(
            DeploymentDetailReader.TargetRow::targetId,
            DeploymentDetailReader.TargetRow::step,
            DeploymentDetailReader.TargetRow::stepState)
        .containsExactly(
            org.assertj.core.groups.Tuple.tuple("tgt_a", "apply", "running"),
            org.assertj.core.groups.Tuple.tuple("tgt_b", "validate", "failed"));
    var other = reader.read("prj_1", "dep_c").targets();
    assertThat(other.get(0).step()).isNull();
    assertThat(other.get(0).stepState()).isNull();
  }

  @Test
  @DisplayName("A-04: 승인 직후면 approval_state approved, 현재 명령이 apply 면 제출 상태가 나와요")
  void approvalStateAndApplyDispatch() {
    seedLogs();
    // dt_a: plan 승인 완료 + apply 명령 접수됨. dt_b: plan 승인 대기 + 현재 명령은 prepare
    jdbc.update(
        "insert into script(id,project_id,target_id,version,source,external_script_id,"
            + "source_deployment_target_id,artifact_ref,content_digest,validated_at)"
            + " values('scr_a','prj_1','tgt_a',1,'s','x1','dt_a','ref','sha256:x',now()),"
            + " ('scr_b','prj_1','tgt_b',1,'s','x2','dt_b','ref','sha256:x',now())");
    for (String[] p :
        new String[][] {
          {"plan_a", "dt_a", "tgt_a", "je_1", "scr_a"}, {"plan_b", "dt_b", "tgt_b", "je_2", "scr_b"}
        }) {
      jdbc.update(
          "insert into plan_revision(id,deployment_target_id,execution_id,project_id,target_id,"
              + "revision,source,source_plan_id,input_hash,script_id,artifact_ref,digest,summary,"
              + "resources,expires_at) values(?,?,?,'prj_1',?,1,'s',?,'ih',?,'ref','dg',"
              + "'{\"counts\":{\"create\":1,\"update\":0,\"delete\":0},\"has_delete\":false,"
              + "\"risks\":[]}'::jsonb,'[]'::jsonb,now()+interval '1 hour')",
          p[0],
          p[1],
          p[3],
          p[2],
          "sp-" + p[0],
          p[4]);
    }
    jdbc.update(
        "insert into approval(id,plan_id,deployment_target_id,state,decision,decided_by,decided_at,"
            + "expires_at) values('apv_a','plan_a','dt_a','approved','approved','acct_1',now(),"
            + "now()+interval '1 hour')");
    jdbc.update(
        "insert into approval(id,plan_id,deployment_target_id,state,expires_at)"
            + " values('apv_b','plan_b','dt_b','pending',now()+interval '1 hour')");
    jdbc.update(
        "insert into jenkins_execution(id,deployment_id,request_id,operation,instance_id,"
            + "job_full_name,request_payload,request_hash,dispatch_status)"
            + " values('je_apply','dep_a','rq_apply','apply','inst','daisy-cd-apply','{}'::jsonb,'h',"
            + "'accepted')");
    jdbc.update(
        "insert into execution_target(execution_id,deployment_target_id,deployment_id)"
            + " values('je_apply','dt_a','dep_a')");
    jdbc.update(
        "update deployment_target set current_plan_id='plan_a', current_execution_id='je_apply',"
            + " status='awaiting_approval' where id='dt_a'");
    jdbc.update(
        "update deployment_target set current_plan_id='plan_b', current_execution_id='je_2',"
            + " status='awaiting_approval' where id='dt_b'");

    var targets = reader.read("prj_1", "dep_a").targets();
    assertThat(targets)
        .extracting(
            DeploymentDetailReader.TargetRow::targetId,
            DeploymentDetailReader.TargetRow::approvalState,
            DeploymentDetailReader.TargetRow::applyDispatch)
        .containsExactly(
            org.assertj.core.groups.Tuple.tuple("tgt_a", "approved", "queued"),
            org.assertj.core.groups.Tuple.tuple("tgt_b", "pending", null));
    var none = reader.read("prj_1", "dep_c").targets().get(0);
    assertThat(none.approvalState()).isNull();
    assertThat(none.applyDispatch()).isNull();
  }
}
