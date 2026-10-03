package com.teamdaisy.server.push;

import static org.assertj.core.api.Assertions.assertThat;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.teamdaisy.server.push.PushDeviceStore.Device;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.atomic.AtomicLong;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.condition.EnabledIfEnvironmentVariable;
import org.springframework.jdbc.core.namedparam.NamedParameterJdbcTemplate;
import org.springframework.jdbc.datasource.DataSourceTransactionManager;

/**
 * 발송기를 실제 PostgreSQL 이벤트·기기 행과 가짜 APNs 로 돌려요.
 *
 * <p>받는 사람 기준(활성 멤버십·활성 계정·켜진 기기), 커서 초기화·전진, 오래된 이벤트, 키 없음, 거절된 토큰 처리를 봐요.
 */
@EnabledIfEnvironmentVariable(named = "DAISY_TEST_DB_URL", matches = ".+")
class PushDispatcherPostgresTest {
  private static final String OWNER_TOKEN = "1".repeat(64);
  private static final String VIEWER_TOKEN = "2".repeat(64);
  private static final ObjectMapper JSON = new ObjectMapper();

  private PushTestSupport.TestDatabase db;
  private FakeSender sender;
  private PushDispatcher dispatcher;
  private final AtomicLong seq = new AtomicLong();

  /** 보낸 내용을 기억하고, 토큰별로 정한 응답을 돌려주는 가짜 APNs 예요. */
  static final class FakeSender implements ApnsSender {
    record Sent(String token, String collapseId, JsonNode payload) {}

    boolean enabled = true;
    final List<Sent> sent = new ArrayList<>();
    final Map<String, Result> responses = new HashMap<>();

    @Override
    public boolean enabled() {
      return enabled;
    }

    @Override
    public Result send(Device device, String collapseId, String payloadJson) {
      try {
        sent.add(new Sent(device.apnsToken(), collapseId, JSON.readTree(payloadJson)));
      } catch (Exception e) {
        throw new IllegalStateException(e);
      }
      Result response = responses.get(device.apnsToken());
      if (response == null) return new Result(200, null);
      if (response.status() < 0) throw new IllegalStateException("boom");
      return response;
    }

    List<Sent> to(String token) {
      return sent.stream().filter(s -> s.token().equals(token)).toList();
    }
  }

  @BeforeEach
  void setup() {
    db = new PushTestSupport.TestDatabase();
    for (String id : List.of("acct_owner", "acct_outsider", "acct_revoked", "acct_off"))
      db.account(id, "owner");
    db.account("acct_viewer", "viewer");
    db.jdbc.update("update account set disabled_at=now() where id='acct_off'");
    project("prj_1", "sample-monolith");
    project("prj_archived", "archived-app");
    db.jdbc.update("update project set archived_at=now() where id='prj_archived'");
    for (String account : List.of("acct_owner", "acct_viewer", "acct_revoked", "acct_off")) {
      member("prj_1", account);
      member("prj_archived", account);
    }
    db.jdbc.update("update project_member set revoked_at=now() where account_id='acct_revoked'");
    var store = new PushDeviceStore(new NamedParameterJdbcTemplate(db.scoped));
    store.upsert("acct_owner", OWNER_TOKEN, "ios", "production");
    store.upsert("acct_viewer", VIEWER_TOKEN, "macos", "sandbox");
    store.upsert("acct_outsider", "3".repeat(64), "ios", "production");
    store.upsert("acct_revoked", "4".repeat(64), "ios", "production");
    store.upsert("acct_off", "5".repeat(64), "ios", "production");
    store.upsert("acct_owner", "6".repeat(64), "ios", "production");
    store.disable("6".repeat(64), "Unregistered");
    for (String dep : List.of("dep_1", "dep_2", "dep_3", "dep_4")) deployment(dep, "prj_1");
    deployment("dep_arch", "prj_archived");
    sender = new FakeSender();
    dispatcher =
        new PushDispatcher(
            new NamedParameterJdbcTemplate(db.scoped),
            new DataSourceTransactionManager(db.scoped),
            store,
            sender);
  }

  @AfterEach
  void cleanup() {
    if (db != null) db.close();
  }

  private void project(String id, String name) {
    db.jdbc.update(
        "insert into project(id,name,repository_id,repository_url,default_branch,created_by)"
            + " values(?,?,?,'https://example.test/repo','main','acct_owner')",
        id,
        name,
        "repo-" + id);
  }

  private void member(String project, String account) {
    db.jdbc.update(
        "insert into project_member(project_id,account_id,granted_by) values(?,?,'acct_owner')",
        project,
        account);
  }

  private void deployment(String id, String project) {
    db.jdbc.update(
        "insert into deployment(id,project_id,requested_by,commit_sha,repository_snapshot,"
            + "input_snapshot,request_hash,status) values(?,?,'acct_owner',?,'{}'::jsonb,'{}'::jsonb,'h','running')",
        id,
        project,
        "a".repeat(40));
  }

  /** 실행부가 남기는 모양 그대로 deployment_log 에 한 줄 넣어요. 기본은 10초 전에 들어온 행이에요. */
  private long log(String deployment, String type, String status, int occurredSecondsAgo) {
    String payload =
        JSON.createObjectNode().put("deployment_id", deployment).put("status", status).toString();
    return db.jdbc.queryForObject(
        "insert into deployment_log(deployment_id,seq,source,source_event_id,payload_hash,"
            + "event_type,payload,occurred_at,received_at) values(?,?,'backend',?,'h',?,"
            + "cast(? as jsonb),now()-make_interval(secs=>?),now()-interval '10 seconds')"
            + " returning id",
        Long.class,
        deployment,
        seq.incrementAndGet(),
        UUID.randomUUID().toString(),
        type,
        payload,
        occurredSecondsAgo);
  }

  private long log(String deployment, String type, String status) {
    return log(deployment, type, status, 1);
  }

  private Long cursor() {
    var rows =
        db.jdbc.queryForList(
            "select last_id from push_cursor where name='deployment_log'", Long.class);
    return rows.isEmpty() ? null : rows.getFirst();
  }

  private long head() {
    return db.jdbc.queryForObject("select coalesce(max(id),0) from deployment_log", Long.class);
  }

  /** 첫 주기는 커서만 만들어요. */
  private void initialise() {
    assertThat(dispatcher.dispatchOnce()).isZero();
    assertThat(cursor()).isEqualTo(head());
  }

  @Test
  @DisplayName("커서가 없으면 지금 끝으로 만들고 쌓인 이벤트는 보내지 않아요")
  void cursorStartsAtHead() {
    log("dep_1", "approval.required", "awaiting_approval");
    long last = log("dep_2", "deployment.completed", "failed");
    assertThat(cursor()).isNull();

    assertThat(dispatcher.dispatchOnce()).isZero();
    assertThat(cursor()).isEqualTo(last);
    assertThat(dispatcher.dispatchOnce()).isZero();
    assertThat(sender.sent).isEmpty();

    log("dep_1", "deployment.completed", "succeeded");
    assertThat(dispatcher.dispatchOnce()).isEqualTo(2);
  }

  @Test
  @DisplayName("대상 3개의 승인 요청은 배포당 한 번, 볼 수 있는 계정의 켜진 기기에만 보내요")
  void approvalIsGroupedPerDeployment() {
    initialise();
    log("dep_1", "approval.required", "awaiting_approval");
    log("dep_1", "approval.required", "awaiting_approval");
    log("dep_1", "approval.required", "awaiting_approval");
    log("dep_1", "deployment.state_changed", "awaiting_approval");
    log("dep_arch", "approval.required", "awaiting_approval");

    assertThat(dispatcher.dispatchOnce()).isEqualTo(2);
    assertThat(sender.sent)
        .extracting(FakeSender.Sent::token)
        .containsExactlyInAnyOrder(OWNER_TOKEN, VIEWER_TOKEN);
    var push = sender.to(OWNER_TOKEN).getFirst();
    assertThat(push.collapseId()).isEqualTo("approval-dep_1");
    JsonNode alert = push.payload().path("aps").path("alert");
    assertThat(alert.path("title-loc-key").asText()).isEqualTo("push.approval.title");
    assertThat(alert.path("loc-key").asText()).isEqualTo("push.approval.body");
    assertThat(alert.path("loc-args")).hasSize(1);
    assertThat(alert.path("loc-args").get(0).asText()).isEqualTo("sample-monolith");
    assertThat(push.payload().path("aps").path("sound").asText()).isEqualTo("default");
    assertThat(push.payload().path("aps").path("thread-id").asText()).isEqualTo("prj_1");
    assertThat(push.payload().path("kind").asText()).isEqualTo("approval_required");
    assertThat(push.payload().path("project_id").asText()).isEqualTo("prj_1");
    assertThat(push.payload().path("deployment_id").asText()).isEqualTo("dep_1");
    assertThat(cursor()).isEqualTo(head());

    // 이미 처리한 이벤트는 다시 보내지 않아요.
    assertThat(dispatcher.dispatchOnce()).isZero();
  }

  @Test
  @DisplayName("완료 상태별 kind·문구 키로 보내고 취소·다른 처리 결과는 건너뛰어요")
  void completionMapsFinalState() {
    initialise();
    log("dep_1", "deployment.completed", "succeeded");
    log("dep_2", "deployment.completed", "partially_succeeded");
    log("dep_3", "deployment.completed", "failed");
    log("dep_4", "deployment.completed", "cancelled");
    long stale = log("dep_4", "deployment.completed", "failed");
    db.jdbc.update("update deployment_log set processing_result='ignored_stale' where id=?", stale);

    assertThat(dispatcher.dispatchOnce()).isEqualTo(6);
    Map<String, JsonNode> byDeployment = new HashMap<>();
    for (var push : sender.to(OWNER_TOKEN)) {
      assertThat(push.collapseId())
          .isEqualTo("result-" + push.payload().path("deployment_id").asText());
      byDeployment.put(push.payload().path("deployment_id").asText(), push.payload());
    }
    assertThat(byDeployment).containsOnlyKeys("dep_1", "dep_2", "dep_3");
    assertThat(byDeployment.get("dep_1").path("kind").asText()).isEqualTo("deployment_succeeded");
    assertThat(byDeployment.get("dep_1").at("/aps/alert/loc-key").asText())
        .isEqualTo("push.succeeded.body");
    assertThat(byDeployment.get("dep_2").path("kind").asText())
        .isEqualTo("deployment_partially_succeeded");
    assertThat(byDeployment.get("dep_2").at("/aps/alert/title-loc-key").asText())
        .isEqualTo("push.partial.title");
    assertThat(byDeployment.get("dep_3").path("kind").asText()).isEqualTo("deployment_failed");
    assertThat(byDeployment.get("dep_3").at("/aps/alert/loc-key").asText())
        .isEqualTo("push.failed.body");
  }

  @Test
  @DisplayName("10분보다 오래된 이벤트는 보내지 않고 커서만 지나가요")
  void oldEventsAreSkipped() {
    initialise();
    log("dep_1", "approval.required", "awaiting_approval", 11 * 60);
    log("dep_2", "deployment.completed", "failed", 9 * 60);

    assertThat(dispatcher.dispatchOnce()).isEqualTo(2);
    assertThat(sender.sent)
        .allSatisfy(push -> assertThat(push.collapseId()).isEqualTo("result-dep_2"));
    assertThat(cursor()).isEqualTo(head());
  }

  @Test
  @DisplayName("방금 들어온 행이 있으면 그 앞까지만 읽고 다음 주기에 이어서 읽어요")
  void waitsForRecentRows() {
    initialise();
    long settled = log("dep_1", "deployment.completed", "succeeded");
    long recent = log("dep_2", "deployment.completed", "failed");
    db.jdbc.update("update deployment_log set received_at=now() where id=?", recent);

    assertThat(dispatcher.dispatchOnce()).isEqualTo(2);
    assertThat(cursor()).isEqualTo(settled);

    db.jdbc.update(
        "update deployment_log set received_at=now()-interval '10 seconds' where id=?", recent);
    assertThat(dispatcher.dispatchOnce()).isEqualTo(2);
    assertThat(cursor()).isEqualTo(recent);
    assertThat(sender.sent)
        .extracting(FakeSender.Sent::collapseId)
        .containsExactlyInAnyOrder("result-dep_1", "result-dep_1", "result-dep_2", "result-dep_2");
  }

  @Test
  @DisplayName("키가 없으면 보내지 않고 커서를 끝에 붙여 둬서 나중에 켜도 지난 이벤트가 나가지 않아요")
  void disabledKeepsCursorAtHead() {
    sender.enabled = false;
    initialise();
    log("dep_1", "approval.required", "awaiting_approval");
    log("dep_2", "deployment.completed", "failed");
    // 방금 들어온 행도 기다리지 않고 끝으로 옮겨요.
    long recent = log("dep_3", "deployment.completed", "failed");
    db.jdbc.update("update deployment_log set received_at=now() where id=?", recent);

    assertThat(dispatcher.dispatchOnce()).isZero();
    assertThat(cursor()).isEqualTo(recent);

    sender.enabled = true;
    assertThat(dispatcher.dispatchOnce()).isZero();
    assertThat(sender.sent).isEmpty();
  }

  @Test
  @DisplayName("BadDeviceToken 이면 기기를 끄고, 다른 실패·예외는 로그만 남기고 커서는 계속 가요")
  void rejectedTokenIsDisabled() {
    initialise();
    sender.responses.put(OWNER_TOKEN, new ApnsSender.Result(400, "BadDeviceToken"));
    sender.responses.put(VIEWER_TOKEN, new ApnsSender.Result(-1, null));
    log("dep_1", "deployment.completed", "succeeded");

    assertThat(dispatcher.dispatchOnce()).isEqualTo(2);
    assertThat(cursor()).isEqualTo(head());
    var owner =
        db.jdbc.queryForMap(
            "select disabled_at,last_error from push_device where apns_token=?", OWNER_TOKEN);
    assertThat(owner.get("disabled_at")).isNotNull();
    assertThat(owner.get("last_error")).isEqualTo("BadDeviceToken");
    assertThat(
            db.jdbc.queryForObject(
                "select disabled_at from push_device where apns_token=?",
                Object.class,
                VIEWER_TOKEN))
        .isNull();

    sender.responses.put(VIEWER_TOKEN, new ApnsSender.Result(500, "InternalServerError"));
    log("dep_2", "deployment.completed", "failed");
    assertThat(dispatcher.dispatchOnce()).isEqualTo(1);
    assertThat(sender.to(OWNER_TOKEN)).hasSize(1);
    assertThat(sender.to(VIEWER_TOKEN)).hasSize(2);
    assertThat(cursor()).isEqualTo(head());
  }

  @Test
  @DisplayName("410 Unregistered 도 기기를 꺼요")
  void unregisteredIsDisabled() {
    initialise();
    sender.responses.put(VIEWER_TOKEN, new ApnsSender.Result(410, "Unregistered"));
    log("dep_1", "approval.required", "awaiting_approval");

    assertThat(dispatcher.dispatchOnce()).isEqualTo(2);
    assertThat(
            db.jdbc.queryForObject(
                "select last_error from push_device where apns_token=?",
                String.class,
                VIEWER_TOKEN))
        .isEqualTo("Unregistered");
  }
}
