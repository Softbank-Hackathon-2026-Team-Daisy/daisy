package com.teamdaisy.server.integration;

import static org.junit.jupiter.api.Assertions.*;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.teamdaisy.server.ai.application.AiUsageService;
import com.teamdaisy.server.common.error.DaisyException;
import com.teamdaisy.server.common.error.ErrorCode;
import com.teamdaisy.server.common.json.CanonicalJson;
import com.teamdaisy.server.deployment.application.*;
import com.teamdaisy.server.deployment.domain.Deployment;
import com.teamdaisy.server.deployment.domain.DeploymentTargetStatus;
import com.teamdaisy.server.deployment.infrastructure.DeploymentStore;
import com.teamdaisy.server.history.application.*;
import com.teamdaisy.server.idempotency.application.IdempotencyService;
import com.teamdaisy.server.jenkins.application.JenkinsCommandService;
import com.teamdaisy.server.jenkins.application.JenkinsConsoleService;
import com.teamdaisy.server.jenkins.infrastructure.JenkinsClient.LogChunk;
import com.teamdaisy.server.script.application.ScriptService;
import java.nio.charset.StandardCharsets;
import java.sql.Connection;
import java.sql.SQLException;
import java.time.Instant;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.UUID;
import java.util.concurrent.Callable;
import java.util.concurrent.CyclicBarrier;
import java.util.concurrent.Executors;
import java.util.concurrent.TimeUnit;
import javax.sql.DataSource;
import org.flywaydb.core.Flyway;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.condition.EnabledIfEnvironmentVariable;
import org.springframework.boot.WebApplicationType;
import org.springframework.boot.autoconfigure.EnableAutoConfiguration;
import org.springframework.boot.autoconfigure.domain.EntityScan;
import org.springframework.boot.builder.SpringApplicationBuilder;
import org.springframework.context.ConfigurableApplicationContext;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.context.annotation.Import;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.AbstractDataSource;
import org.springframework.jdbc.datasource.DriverManagerDataSource;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;

/** PostgreSQL only. Each test owns one new schema; no external worker/client is registered. */
@EnabledIfEnvironmentVariable(named = "DAISY_TEST_DB_URL", matches = ".+")
class ExecutionPostgresTest {
  private static final String COMMIT = "a".repeat(40), DIGEST = "sha256:" + "b".repeat(64);
  private final String schema = "daisy_it_" + UUID.randomUUID().toString().replace("-", "");
  private DataSource base;
  private ConfigurableApplicationContext context;
  private JdbcTemplate jdbc;
  private DeploymentExecutionService execution;
  private ObjectMapper mapper;

  @BeforeEach
  void setup() throws Exception {
    assertTrue(schema.matches("daisy_it_[a-f0-9]{32}"));
    base =
        new DriverManagerDataSource(
            required("DAISY_TEST_DB_URL"),
            required("DAISY_TEST_DB_USER"),
            required("DAISY_TEST_DB_PASSWORD"));
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
              statement.execute("SET statement_timeout='15s'");
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
    context =
        new SpringApplicationBuilder(TestConfig.class)
            .web(WebApplicationType.NONE)
            .initializers(
                application -> application.getBeanFactory().registerSingleton("dataSource", scoped))
            .properties(
                Map.of(
                    "spring.flyway.enabled",
                    "false",
                    "spring.jpa.hibernate.ddl-auto",
                    "validate",
                    "spring.jpa.open-in-view",
                    "false",
                    "spring.jackson.property-naming-strategy",
                    "SNAKE_CASE",
                    "spring.jmx.enabled",
                    "false",
                    "daisy.jenkins.instance-id",
                    "test-instance",
                    "daisy.jenkins.console-enabled",
                    "true",
                    "daisy.jenkins.console-sanitized-utf8-confirmed",
                    "true"))
            .run();
    jdbc = context.getBean(JdbcTemplate.class);
    execution = context.getBean(DeploymentExecutionService.class);
    mapper = context.getBean(ObjectMapper.class);
    jdbc.update(
        "insert into account(id,username,password_hash,display_name,role) values('acct_1','fixture','TEST-ONLY-HASH','Fixture','owner')");
    jdbc.update(
        "insert into project(id,name,repository_id,repository_url,default_branch,created_by) values('prj_1','Fixture','repo-1','https://example.test/repo','main','acct_1')");
    jdbc.update(
        "insert into project_member(project_id,account_id,granted_by) values('prj_1','acct_1','acct_1')");
    jdbc.update(
        "insert into target(id,project_id,name,environment_type,state_identity,config) values('tgt_1','prj_1','Fixture target','onprem','test:shared-state','{}')");
  }

  @AfterEach
  void cleanup() {
    if (context != null) context.close();
    if (base != null && schema.matches("daisy_it_[a-f0-9]{32}"))
      new JdbcTemplate(base).execute("DROP SCHEMA IF EXISTS " + schema + " CASCADE");
  }

  private static String required(String name) {
    return Objects.requireNonNull(System.getenv(name), name + " must be set for this test");
  }

  private TransactionTemplate transaction() {
    return new TransactionTemplate(context.getBean(PlatformTransactionManager.class));
  }

  private DeploymentExecutionService.CreateRequest createRequest(String key) {
    return new DeploymentExecutionService.CreateRequest(
        "acct_1",
        "prj_1",
        COMMIT,
        List.of("tgt_1"),
        mapper.createObjectNode().put("hash_format_version", 1),
        key);
  }

  private long count(String table) {
    return Objects.requireNonNull(jdbc.queryForObject("select count(*) from " + table, Long.class));
  }

  private String value(String column, String table, String id) {
    return jdbc.queryForObject(
        "select " + column + " from " + table + " where id=?", String.class, id);
  }

  @Test
  void concurrentIdempotencyCreatesExactlyOneDeploymentAndConflictsRollback() throws Exception {
    var responses =
        concurrent(
            () -> execution.create(createRequest("same-key")),
            () -> execution.create(createRequest("same-key")));
    assertEquals(responses.get(0), responses.get(1));
    assertEquals(1, count("deployment"));
    assertEquals(1, count("idempotency"));
    assertEquals(1, count("jenkins_execution"));
    var different =
        new DeploymentExecutionService.CreateRequest(
            "acct_1",
            "prj_1",
            "c".repeat(40),
            List.of("tgt_1"),
            mapper.createObjectNode().put("hash_format_version", 1),
            "same-key");
    assertEquals(
        ErrorCode.STATE_CONFLICT,
        assertThrows(DaisyException.class, () -> execution.create(different)).errorCode());
    assertEquals(1, count("deployment"));
    assertEquals(1, count("idempotency"));
  }

  @Test
  void realCreateBuildPlanApproveSuccessAndTerminalReplayAreAtomic() {
    Prepared prepared = prepare("flow");
    execution.decide(decision(prepared, "approval-key"));
    assertEquals(1, count("target_lock"));
    String apply = value("current_execution_id", "deployment_target", prepared.target());
    long approvedSeq =
        jdbc.queryForObject(
            "select last_event_seq from deployment where id=?", Long.class, prepared.deployment());
    execution.acceptPlan(
        prepared.planReceipt()); // The original receipt is now stale under the new APPLY owner.
    assertEquals(
        approvedSeq,
        jdbc.queryForObject(
            "select last_event_seq from deployment where id=?", Long.class, prepared.deployment()));
    assertEquals(apply, value("current_execution_id", "deployment_target", prepared.target()));
    assertEquals("approved", value("state", "approval", prepared.approval()));
    execution.acceptState(
        state(prepared, apply, "applying", 1, DeploymentTargetStatus.APPLYING, null));
    var result =
        mapper
            .createObjectNode()
            .put("plan_id", prepared.plan())
            .put("plan_digest", DIGEST)
            .put("input_hash", prepared.inputHash());
    result.set("image_refs", prepared.images());
    var success = state(prepared, apply, "success", 2, DeploymentTargetStatus.SUCCEEDED, result);
    execution.acceptState(success);
    assertEquals("succeeded", value("status", "deployment", prepared.deployment()));
    assertEquals(0, count("target_lock"));
    long seq =
        jdbc.queryForObject(
            "select last_event_seq from deployment where id=?", Long.class, prepared.deployment());
    execution.acceptState(success);
    assertEquals(
        seq,
        jdbc.queryForObject(
            "select last_event_seq from deployment where id=?", Long.class, prepared.deployment()));
    assertEquals(
        ErrorCode.STATE_CONFLICT,
        assertThrows(
                DaisyException.class,
                () ->
                    execution.acceptState(
                        state(prepared, apply, "success", 2, DeploymentTargetStatus.FAILED, null)))
            .errorCode());
    assertEquals("succeeded", value("status", "deployment", prepared.deployment()));
    long journalSeq =
        jdbc.queryForObject(
            "select max(seq) from deployment_log where deployment_id=?",
            Long.class,
            prepared.deployment());
    assertEquals(seq, journalSeq); // JPA dirty flushes must not overwrite JDBC-assigned counters.
    var usage =
        context
            .getBean(AiUsageService.class)
            .receive(
                prepared.prepare(),
                prepared.deployment(),
                prepared.target(),
                new AiUsageService.UsageInput(
                    "test:" + prepared.prepare(),
                    "late-call",
                    "test",
                    "test-model",
                    "generate",
                    1,
                    "unknown",
                    null,
                    null,
                    null,
                    null,
                    null,
                    Instant.now()));
    assertFalse(usage.duplicate());
    assertNull(
        jdbc.queryForObject(
            "select cost_usd from ai_usage where id=?", java.math.BigDecimal.class, usage.id()));
    assertEquals("succeeded", value("status", "deployment", prepared.deployment()));
  }

  @Test
  void cancelledQueueRemainsClaimableUntilTargetsAndLockAreFinished() {
    Prepared prepared = prepare("queue-cancel");
    jdbc.update(
        "update jenkins_execution set dispatch_status='accepted',run_status='succeeded' where id=?",
        prepared.prepare());
    execution.decide(decision(prepared, "queue-approval"));
    String apply = value("current_execution_id", "deployment_target", prepared.target());
    var commands = context.getBean(JenkinsCommandService.class);
    assertEquals(apply, commands.claimPending().id());
    commands.dispatched(apply, 17L, null, "queued");
    commands.observed(apply, null, "cancelled");
    assertEquals(1, count("target_lock"));
    assertEquals(apply, commands.claimCheck().id());
    execution.onQueueCancelled(apply);
    execution.onQueueCancelled(apply);
    assertEquals("cancelled", value("status", "deployment_target", prepared.target()));
    assertEquals(
        "cancelled",
        jdbc.queryForObject(
            "select status from execution_target where execution_id=? and deployment_target_id=?",
            String.class,
            apply,
            prepared.target()));
    assertEquals(0, count("target_lock"));
    assertNull(commands.claimCheck());
  }

  @Test
  void simultaneousApprovalOfSameStateAllowsOneAndRollsBackOtherDecision() throws Exception {
    Prepared first = prepare("first"), second = prepare("second");
    var outcomes = concurrent(() -> approveOutcome(first), () -> approveOutcome(second));
    assertEquals(1, outcomes.stream().filter("accepted"::equals).count());
    assertEquals(1, outcomes.stream().filter("TARGET_LOCKED"::equals).count());
    assertEquals(1, count("target_lock"));
    assertEquals(
        1, jdbc.queryForObject("select count(*) from approval where state='approved'", Long.class));
    assertEquals(
        1, jdbc.queryForObject("select count(*) from approval where state='pending'", Long.class));
    assertEquals(
        1,
        jdbc.queryForObject(
            "select count(*) from jenkins_execution where operation='apply'", Long.class));
  }

  @Test
  void pendingApplyCancellationRecordsTerminalEvidenceAndReleasesOnlyItsLock() {
    Prepared prepared = prepare("cancel-pending");
    execution.decide(decision(prepared, "approve-before-cancel"));
    String apply = value("current_execution_id", "deployment_target", prepared.target());
    assertEquals("pending", value("dispatch_status", "jenkins_execution", apply));
    assertEquals(1, count("target_lock"));
    execution.cancel(
        new DeploymentExecutionService.ControlRequest(
            "acct_1", "prj_1", prepared.deployment(), List.of("tgt_1"), "cancel-key"));
    assertEquals("cancelled", value("status", "deployment", prepared.deployment()));
    assertEquals("cancelled", value("status", "deployment_target", prepared.target()));
    assertEquals("rejected", value("dispatch_status", "jenkins_execution", apply));
    assertEquals(
        "cancelled",
        jdbc.queryForObject(
            "select status from execution_target where execution_id=? and deployment_target_id=?",
            String.class,
            apply,
            prepared.target()));
    assertNotNull(
        jdbc.queryForObject(
            "select finished_at from execution_target where execution_id=? and deployment_target_id=?",
            java.sql.Timestamp.class,
            apply,
            prepared.target()));
    assertEquals(0, count("target_lock"));
    assertEquals(
        0,
        jdbc.queryForObject(
            "select count(*) from jenkins_execution where operation='stop'", Long.class));
    assertEquals(
        1,
        jdbc.queryForObject(
            "select count(*) from deployment_log where execution_id=? and payload->>'reason'='confirmed_not_submitted'",
            Long.class,
            apply));
  }

  @Test
  void confirmedStaleReplansWithoutIncreasingAttemptAndReplaysWithoutAnotherCommand() {
    Prepared prepared = prepare("stale");
    execution.decide(decision(prepared, "approve-before-stale"));
    String apply = value("current_execution_id", "deployment_target", prepared.target());
    jdbc.update(
        "update jenkins_execution set dispatch_status='accepted',run_status='succeeded',build_number=1,finished_at=now() where id=?",
        apply);
    int attempt =
        jdbc.queryForObject(
            "select attempt from deployment_target where id=?", Integer.class, prepared.target());
    var stale =
        new DeploymentExecutionService.StaleResult(
            "prj_1",
            prepared.deployment(),
            apply,
            prepared.target(),
            "test:" + apply,
            "stale-proof",
            1,
            prepared.plan(),
            DIGEST,
            prepared.inputHash(),
            true,
            true,
            Instant.now());
    execution.acceptStale(stale);
    assertEquals(0, count("target_lock"));
    assertEquals("validating", value("status", "deployment_target", prepared.target()));
    assertNull(value("current_plan_id", "deployment_target", prepared.target()));
    assertEquals(
        attempt,
        jdbc.queryForObject(
            "select attempt from deployment_target where id=?", Integer.class, prepared.target()));
    assertEquals("superseded", value("state", "plan_revision", prepared.plan()));
    assertEquals("superseded", value("state", "approval", prepared.approval()));
    assertEquals("approved", value("decision", "approval", prepared.approval()));
    String replan = value("current_execution_id", "deployment_target", prepared.target());
    assertNotEquals(apply, replan);
    assertEquals("replan", value("operation", "jenkins_execution", replan));
    assertEquals(apply, value("parent_execution_id", "jenkins_execution", replan));
    assertEquals(
        "stale",
        jdbc.queryForObject(
            "select status from execution_target where execution_id=? and deployment_target_id=?",
            String.class,
            apply,
            prepared.target()));
    long commands = count("jenkins_execution");
    long seq =
        jdbc.queryForObject(
            "select last_event_seq from deployment where id=?", Long.class, prepared.deployment());
    execution.acceptStale(stale);
    assertEquals(commands, count("jenkins_execution"));
    assertEquals(
        seq,
        jdbc.queryForObject(
            "select last_event_seq from deployment where id=?", Long.class, prepared.deployment()));
  }

  @Test
  void retryKeepsFailedTargetLineageAndFrozenInput() {
    Prepared prepared = prepare("retry-source");
    execution.decide(decision(prepared, "retry-approval"));
    String apply = value("current_execution_id", "deployment_target", prepared.target());
    execution.acceptState(state(prepared, apply, "failed", 1, DeploymentTargetStatus.FAILED, null));
    assertEquals("failed", value("status", "deployment", prepared.deployment()));
    String retry =
        execution
            .retry(
                new DeploymentExecutionService.ControlRequest(
                    "acct_1", "prj_1", prepared.deployment(), List.of("tgt_1"), "retry-key"))
            .body()
            .path("deployment_id")
            .asText();
    String target =
        jdbc.queryForObject(
            "select id from deployment_target where deployment_id=?", String.class, retry);
    assertEquals("retry", value("kind", "deployment", retry));
    assertEquals(prepared.deployment(), value("retry_of_deployment_id", "deployment", retry));
    assertEquals(
        prepared.target(), value("retry_of_deployment_target_id", "deployment_target", target));
    assertEquals(prepared.inputHash(), value("input_hash", "deployment_target", target));
    assertEquals(
        jdbc.queryForObject(
            "select input_snapshot::text from deployment where id=?",
            String.class,
            prepared.deployment()),
        jdbc.queryForObject(
            "select input_snapshot::text from deployment where id=?", String.class, retry));
    assertEquals(
        jdbc.queryForObject(
            "select target_snapshot::text from deployment_target where id=?",
            String.class,
            prepared.target()),
        jdbc.queryForObject(
            "select target_snapshot::text from deployment_target where id=?",
            String.class,
            target));
    assertEquals("failed", value("status", "deployment_target", prepared.target()));
  }

  @Test
  void rollbackRestoresSuccessfulSourceImageAndScriptWithoutAiAutofix() throws Exception {
    Prepared prepared = prepare("rollback-source");
    execution.decide(decision(prepared, "rollback-approval"));
    String apply = value("current_execution_id", "deployment_target", prepared.target());
    var result =
        mapper
            .createObjectNode()
            .put("plan_id", prepared.plan())
            .put("plan_digest", DIGEST)
            .put("input_hash", prepared.inputHash());
    result.set("image_refs", prepared.images());
    execution.acceptState(
        state(prepared, apply, "success", 1, DeploymentTargetStatus.SUCCEEDED, result));
    String rollback =
        execution
            .rollback(
                new DeploymentExecutionService.RollbackRequest(
                    "acct_1", "prj_1", prepared.deployment(), null, "rollback-key"))
            .body()
            .path("deployment_id")
            .asText();
    String target =
        jdbc.queryForObject(
            "select id from deployment_target where deployment_id=?", String.class, rollback);
    String command = value("current_execution_id", "deployment_target", target);
    assertEquals(prepared.deployment(), value("rollback_of_deployment_id", "deployment", rollback));
    assertEquals(
        value("source_version_id", "deployment", prepared.deployment()),
        value("source_version_id", "deployment", rollback));
    assertEquals(
        jdbc.queryForObject(
            "select image_refs::text from deployment where id=?",
            String.class,
            prepared.deployment()),
        jdbc.queryForObject(
            "select image_refs::text from deployment where id=?", String.class, rollback));
    assertEquals(
        prepared.target(),
        value("restored_from_deployment_target_id", "deployment_target", target));
    String script = value("script_id", "deployment_target", prepared.target());
    assertEquals(script, value("script_id", "deployment_target", target));
    JsonNode payload =
        mapper.readTree(
            jdbc.queryForObject(
                "select request_payload::text from jenkins_execution where id=?",
                String.class,
                command));
    assertFalse(payload.path("allow_ai_autofix").asBoolean(true));
    assertEquals(script, payload.path("restore_scripts").get(0).path("script_id").asText());
    assertEquals(
        prepared.target(),
        payload.path("restore_scripts").get(0).path("restored_from_deployment_target_id").asText());
  }

  @Test
  void interruptedDispatchBecomesUnknownWithoutAnotherCommand() {
    String deployment =
        execution.create(createRequest("dispatch-recovery")).body().path("deployment_id").asText();
    var commands = context.getBean(JenkinsCommandService.class);
    String command = commands.claimPending().id();
    assertEquals("dispatching", value("dispatch_status", "jenkins_execution", command));
    long before = count("jenkins_execution");
    commands.recoverDispatching();
    commands.recoverDispatching();
    assertEquals("unknown", value("dispatch_status", "jenkins_execution", command));
    assertEquals("dispatch_interrupted", value("last_error", "jenkins_execution", command));
    assertNull(commands.claimPending());
    assertEquals(command, commands.claimCheck().id());
    assertEquals(before, count("jenkins_execution"));
    assertEquals(deployment, value("deployment_id", "jenkins_execution", command));
  }

  @Test
  void rollbackRemovesEventAndCounterAlongWithManagedState() {
    String id =
        execution.create(createRequest("rollback-check")).body().path("deployment_id").asText();
    long before =
        jdbc.queryForObject("select last_event_seq from deployment where id=?", Long.class, id);
    long rows = count("deployment_log");
    assertThrows(
        DaisyException.class,
        () ->
            transaction()
                .execute(
                    status -> {
                      Deployment deployment =
                          context.getBean(DeploymentStore.class).lock("prj_1", id);
                      deployment.markStarted(Instant.now());
                      context.getBean(DeploymentStore.class).flush();
                      context
                          .getBean(EventJournal.class)
                          .appendDeployment(
                              "prj_1",
                              id,
                              new DeploymentEvent(
                                  "test",
                                  "rolled-back",
                                  null,
                                  null,
                                  null,
                                  "deployment.state_changed",
                                  null,
                                  null,
                                  "info",
                                  null,
                                  mapper.createObjectNode().put("status", "running"),
                                  "applied",
                                  null,
                                  null,
                                  null,
                                  Instant.now()),
                              false);
                      throw new DaisyException(ErrorCode.STATE_CONFLICT);
                    }));
    assertEquals("queued", value("status", "deployment", id));
    assertEquals(rows, count("deployment_log"));
    assertEquals(
        before,
        jdbc.queryForObject("select last_event_seq from deployment where id=?", Long.class, id));
  }

  @Test
  void consoleOwnerUtf8EofRollbackAndReplayUseAtomicPersistedCursor() {
    String deployment =
        execution.create(createRequest("console")).body().path("deployment_id").asText();
    String target =
        jdbc.queryForObject(
            "select id from deployment_target where deployment_id=?", String.class, deployment);
    String command = value("current_execution_id", "deployment_target", target);
    jdbc.update(
        "update jenkins_execution set dispatch_status='accepted',run_status='running',build_number=7 where id=?",
        command);
    var consoles = context.getBean(JenkinsConsoleService.class);
    var owner = consoles.owner(command);
    assertEquals(command, owner.id());
    assertEquals(command, value("log_owner_execution_id", "jenkins_execution", command));
    String follower =
        transaction()
            .execute(
                status ->
                    context
                        .getBean(JenkinsCommandService.class)
                        .enqueue(
                            deployment, "prepare", command, List.of(), mapper.createObjectNode())
                        .id());
    jdbc.update(
        "update jenkins_execution set dispatch_status='accepted',run_status='running',build_number=7 where id=?",
        follower);
    assertEquals(command, consoles.owner(follower).id());
    assertEquals(command, value("log_owner_execution_id", "jenkins_execution", follower));
    assertEquals(
        1,
        jdbc.queryForObject(
            "select count(*) from jenkins_execution where build_number=7 and log_owner_execution_id=id",
            Long.class));

    long rows = count("deployment_log");
    long seq =
        jdbc.queryForObject(
            "select last_event_seq from deployment where id=?", Long.class, deployment);
    byte[] secret = "token=\nsensitive-value\n".getBytes(StandardCharsets.UTF_8);
    assertThrows(
        DaisyException.class,
        () -> consoles.commit(owner, new LogChunk(secret, secret.length, false)));
    assertEquals(
        0L,
        jdbc.queryForObject(
            "select log_cursor from jenkins_execution where id=?", Long.class, command));
    assertEquals(rows, count("deployment_log"));

    byte[] text = "가\n끝".getBytes(StandardCharsets.UTF_8);
    var eof = new LogChunk(text, text.length, false);
    // Force failure after the public event insert: the REQUIRES_NEW transaction must roll both
    // back.
    jdbc.execute(
        """
        create function reject_console_cursor() returns trigger language plpgsql as $$
        begin
          if NEW.log_cursor>OLD.log_cursor then raise exception 'TEST console cursor rollback'; end if;
          return NEW;
        end $$
        """);
    jdbc.execute(
        "create trigger console_cursor_failure before update of log_cursor on jenkins_execution for each row execute function reject_console_cursor()");
    assertThrows(
        org.springframework.dao.DataAccessException.class, () -> consoles.commit(owner, eof));
    assertEquals(rows, count("deployment_log"));
    assertEquals(
        seq,
        jdbc.queryForObject(
            "select last_event_seq from deployment where id=?", Long.class, deployment));
    assertEquals(
        0L,
        jdbc.queryForObject(
            "select log_cursor from jenkins_execution where id=?", Long.class, command));
    assertFalse(
        jdbc.queryForObject(
            "select log_complete from jenkins_execution where id=?", Boolean.class, command));
    jdbc.execute("drop trigger console_cursor_failure on jenkins_execution");
    jdbc.execute("drop function reject_console_cursor()");

    assertTrue(consoles.commit(owner, eof));
    assertEquals(
        (long) text.length,
        jdbc.queryForObject(
            "select log_cursor from jenkins_execution where id=?", Long.class, command));
    assertTrue(
        jdbc.queryForObject(
            "select log_complete from jenkins_execution where id=?", Boolean.class, command));
    assertEquals(
        "가\n끝",
        jdbc.queryForObject(
            "select message from deployment_log where source_stream=?",
            String.class,
            owner.stream()));
    assertEquals(
        (long) text.length,
        jdbc.queryForObject(
            "select source_end_offset from deployment_log where source_stream=?",
            Long.class,
            owner.stream()));
    assertEquals(rows + 1, count("deployment_log"));
    assertEquals(
        seq + 1,
        jdbc.queryForObject(
            "select last_event_seq from deployment where id=?", Long.class, deployment));
    assertFalse(consoles.commit(owner, eof));
    assertEquals(rows + 1, count("deployment_log"));
    assertEquals(
        seq + 1,
        jdbc.queryForObject(
            "select last_event_seq from deployment where id=?", Long.class, deployment));
    assertEquals("waiting", value("status", "deployment_target", target));
    assertEquals("queued", value("status", "deployment", deployment));
    assertEquals("running", value("run_status", "jenkins_execution", command));
  }

  @Test
  void compositeForeignKeysRejectTargetFromAnotherProject() {
    String deployment =
        execution.create(createRequest("scope-check")).body().path("deployment_id").asText();
    jdbc.update(
        "insert into project(id,name,repository_id,repository_url,default_branch,created_by) values('prj_other','Other','repo-other','https://example.test/other','main','acct_1')");
    jdbc.update(
        "insert into target(id,project_id,name,environment_type,state_identity,config) values('tgt_other','prj_other','Other','aws','test:other-state','{}')");
    assertThrows(
        org.springframework.dao.DataIntegrityViolationException.class,
        () ->
            jdbc.update(
                "insert into deployment_target(id,deployment_id,project_id,target_id,target_snapshot,state_identity) values('dt_wrong',?,'prj_1','tgt_other','{}','test:other-state')",
                deployment));
    assertEquals(1, count("deployment_target"));
  }

  private record Prepared(
      String deployment,
      String target,
      String prepare,
      String plan,
      String approval,
      String inputHash,
      JsonNode images,
      DeploymentExecutionService.PlanResult planReceipt) {}

  private Prepared prepare(String key) {
    String deployment = execution.create(createRequest(key)).body().path("deployment_id").asText();
    String target =
        jdbc.queryForObject(
            "select id from deployment_target where deployment_id=?", String.class, deployment);
    String command = value("current_execution_id", "deployment_target", target);
    String source = "test:" + command;
    var images = mapper.createObjectNode();
    images
        .putObject("app")
        .put("image_ref", "registry.test/app:" + COMMIT)
        .put("commit_sha", COMMIT)
        .put("digest", DIGEST);
    execution.bindBuildResult(
        new DeploymentExecutionService.BuildResult(
            "prj_1",
            deployment,
            command,
            source,
            "build",
            "src_" + key,
            COMMIT,
            images,
            Instant.now()));
    var script =
        context
            .getBean(ScriptService.class)
            .receive(
                command,
                deployment,
                target,
                new ScriptService.ScriptInput(
                    source,
                    "code",
                    "artifact:code-" + key,
                    DIGEST,
                    null,
                    null,
                    Instant.now(),
                    null));
    Prepared initial =
        new Prepared(
            deployment,
            target,
            command,
            null,
            null,
            value("input_hash", "deployment_target", target),
            images,
            null);
    execution.acceptState(
        state(initial, command, "generating", 1, DeploymentTargetStatus.GENERATING, null));
    var summary = mapper.createObjectNode().put("has_delete", false);
    summary.putObject("counts").put("create", 1).put("update", 0).put("delete", 0);
    summary.putArray("risks");
    var receipt =
        new DeploymentExecutionService.PlanResult(
            "prj_1",
            deployment,
            command,
            target,
            source,
            "plan",
            2,
            "plan-1",
            initial.inputHash(),
            script.id(),
            false,
            1,
            "artifact:plan-" + key,
            DIGEST,
            summary,
            mapper.createArrayNode(),
            Instant.now().plusSeconds(3600),
            null,
            Instant.now());
    execution.acceptPlan(receipt);
    String plan = value("current_plan_id", "deployment_target", target);
    String approval =
        jdbc.queryForObject("select id from approval where plan_id=?", String.class, plan);
    return new Prepared(
        deployment, target, command, plan, approval, initial.inputHash(), images, receipt);
  }

  private DeploymentExecutionService.DecisionRequest decision(Prepared p, String key) {
    return new DeploymentExecutionService.DecisionRequest(
        "acct_1",
        "prj_1",
        p.deployment(),
        Map.of("tgt_1", new DeploymentExecutionService.Decision(p.approval(), true, null)),
        key);
  }

  private String approveOutcome(Prepared p) {
    try {
      execution.decide(decision(p, "approve-" + p.deployment()));
      return "accepted";
    } catch (DaisyException error) {
      return error.errorCode().name();
    }
  }

  private DeploymentExecutionService.StateResult state(
      Prepared p,
      String command,
      String event,
      long sequence,
      DeploymentTargetStatus state,
      JsonNode result) {
    return new DeploymentExecutionService.StateResult(
        "prj_1",
        p.deployment(),
        command,
        p.target(),
        "test:" + command,
        event,
        sequence,
        state,
        1,
        null,
        result,
        Instant.now());
  }

  private static <T> List<T> concurrent(Callable<T> first, Callable<T> second) throws Exception {
    try (var pool = Executors.newFixedThreadPool(2)) {
      var barrier = new CyclicBarrier(2);
      var a =
          pool.submit(
              () -> {
                barrier.await(5, TimeUnit.SECONDS);
                return first.call();
              });
      var b =
          pool.submit(
              () -> {
                barrier.await(5, TimeUnit.SECONDS);
                return second.call();
              });
      return List.of(a.get(15, TimeUnit.SECONDS), b.get(15, TimeUnit.SECONDS));
    }
  }

  @Configuration(proxyBeanMethods = false)
  @EnableAutoConfiguration
  @EntityScan("com.teamdaisy.server")
  @Import({
    DeploymentStore.class,
    DeploymentExecutionService.class,
    JenkinsCommandService.class,
    ScriptService.class,
    AiUsageService.class,
    EventJournal.class,
    IdempotencyService.class,
    CanonicalJson.class,
    JenkinsConsoleService.class
  })
  static class TestConfig {
    // MOCK: fixture-only identity/project adapters; production EH policies are not implemented
    // here.
    @Bean
    ExecutionAccess access(JdbcTemplate jdbc) {
      return new ExecutionAccess() {
        @Override
        public void requireRead(String actor, String project) {
          requireWrite(actor, project);
        }

        @Override
        public void requireWrite(String actor, String project) {
          Long count =
              jdbc.queryForObject(
                  "select count(*) from account a join project_member m on m.account_id=a.id where a.id=? and m.project_id=? and a.disabled_at is null and m.revoked_at is null",
                  Long.class,
                  actor,
                  project);
          if (count == null || count != 1) throw new DaisyException(ErrorCode.FORBIDDEN);
        }
      };
    }

    @Bean
    ExecutionInputs inputs(JdbcTemplate jdbc, ObjectMapper mapper) {
      return new ExecutionInputs() {
        @Override
        public Captured capture(
            String actor, String project, String commit, List<String> targets, JsonNode input) {
          var selected =
              targets.stream()
                  .map(
                      id -> {
                        var row =
                            jdbc.queryForMap(
                                "select name,state_identity from target where id=? and project_id=?",
                                id,
                                project);
                        return new TargetInput(
                            id,
                            mapper
                                .createObjectNode()
                                .put("name", (String) row.get("name"))
                                .put("config_revision", 1),
                            (String) row.get("state_identity"));
                      })
                  .toList();
          return new Captured(
              mapper.createObjectNode().put("repository_id", "repo-1"), input, selected, null);
        }

        @Override
        public void verifyFrozen(String actor, String project, FrozenInput input) {}

        @Override
        public BuildInput recordBuild(DeploymentExecutionService.BuildResult result) {
          jdbc.update(
              "insert into source_version(id,project_id,source,external_build_id,commit_sha,status,image_refs) values(?,?,?,?,?,'succeeded',cast(? as jsonb))",
              result.sourceVersionId(),
              result.projectId(),
              result.source(),
              result.sourceEventId(),
              result.commitSha(),
              result.imageRefs().toString());
          return new BuildInput(result.sourceVersionId(), result.commitSha(), result.imageRefs());
        }
      };
    }
  }
}
