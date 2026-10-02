package com.teamdaisy.server.integration;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import java.sql.Connection;
import java.util.List;
import java.util.UUID;
import org.flywaydb.core.Flyway;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.condition.EnabledIfEnvironmentVariable;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.DriverManagerDataSource;
import org.springframework.jdbc.datasource.SingleConnectionDataSource;

@EnabledIfEnvironmentVariable(named = "DAISY_TEST_DB_URL", matches = ".+")
class AzureMigrationPostgresTest {
  @Test
  void upgradesV1WithoutChangingExistingTargets() throws Exception {
    String schema = "azure_it_" + UUID.randomUUID().toString().replace("-", "");
    var base =
        new DriverManagerDataSource(
            System.getenv("DAISY_TEST_DB_URL"),
            System.getenv("DAISY_TEST_DB_USER"),
            System.getenv("DAISY_TEST_DB_PASSWORD"));
    try (Connection connection = base.getConnection()) {
      var scoped = new SingleConnectionDataSource(connection, true);
      var jdbc = new JdbcTemplate(scoped);
      jdbc.execute("CREATE SCHEMA " + schema);
      try {
        connection.setSchema(schema);
        Flyway.configure().dataSource(scoped).defaultSchema(schema).target("1").load().migrate();
        jdbc.update(
            "insert into account(id,username,password_hash,display_name,role)"
                + " values('acct_azure','azure-test','TEST-ONLY-HASH','Fixture','owner')");
        jdbc.update(
            "insert into project(id,name,repository_id,repository_url,default_branch,created_by)"
                + " values('prj_azure','Fixture','repo-azure','https://example.test/repo','main','acct_azure')");
        for (String env : List.of("onprem", "aws", "gcp")) {
          target(jdbc, env);
        }
        assertThatThrownBy(() -> target(jdbc, "azure"))
            .isInstanceOf(DataIntegrityViolationException.class);
        var flyway = Flyway.configure().dataSource(scoped).defaultSchema(schema).load();
        assertThat(flyway.migrate().migrationsExecuted).isEqualTo(1);
        flyway.validate();
        target(jdbc, "azure");
        assertThat(jdbc.queryForList("select environment_type from target", String.class))
            .containsExactlyInAnyOrder("onprem", "aws", "gcp", "azure");
        assertThatThrownBy(() -> target(jdbc, "invalid"))
            .isInstanceOf(DataIntegrityViolationException.class);
        assertThat(flyway.migrate().migrationsExecuted).isZero();
      } finally {
        connection.setSchema("public");
        jdbc.execute("DROP SCHEMA " + schema + " CASCADE");
      }
    }
  }

  private static void target(JdbcTemplate jdbc, String env) {
    jdbc.update(
        "insert into target(id,project_id,name,environment_type,state_identity,config)"
            + " values(?,'prj_azure',?,?,?,'{}'::jsonb)",
        "tgt_" + env,
        env,
        env,
        "state:" + env);
  }
}
