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
}
