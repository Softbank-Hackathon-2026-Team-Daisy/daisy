package com.teamdaisy.server.push;

import com.teamdaisy.server.push.ApnsSender.Result;
import com.teamdaisy.server.push.PushDeviceStore.Device;
import com.teamdaisy.server.push.PushMessages.Notification;
import com.teamdaisy.server.push.PushMessages.PushEvent;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.jdbc.core.namedparam.NamedParameterJdbcTemplate;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;

/**
 * 배포 이벤트를 읽어 APNs 로 보내요 (ios/SPEC.md §6-5 P-02).
 *
 * <p>원본은 {@code deployment_log} 예요. {@code approval.required}·{@code deployment.completed} 는 {@code
 * EventJournal} 이 {@code project_event} 로 옮기지 않아서 그쪽에서는 보이지 않아요. 실행부 코드는 건드리지 않고 이 테이블을 읽기 전용으로만
 * 읽어요.
 *
 * <p>한 번에 하는 일:
 *
 * <ol>
 *   <li>트랜잭션 안에서 {@code push_cursor} 행을 {@code FOR UPDATE} 로 잡고, 커서 뒤 이벤트를 읽고, 커서를 옮겨요. 여러 인스턴스가 떠도
 *       같은 이벤트를 두 번 가져가지 않아요.
 *   <li>커밋한 뒤 트랜잭션 밖에서 APNs 로 보내요. 실패는 로그만 남기고 다시 시도하지 않아요. 알림은 놓쳐도 되지만 커서가 멈추면 안 돼요.
 * </ol>
 *
 * <p>막 쓰인 행 뒤로 먼저 커밋된 행이 커서를 앞질러 가지 않게, 2초 안에 들어온 행이 있으면 그 앞까지만 읽어요. 10분보다 오래된 이벤트는 보내지 않고 건너뛰어요.
 */
@Component
public class PushDispatcher {
  static final String CURSOR = "deployment_log";
  static final int BATCH = 200;
  private static final Logger LOG = LoggerFactory.getLogger(PushDispatcher.class);

  private final NamedParameterJdbcTemplate jdbc;
  private final TransactionTemplate transaction;
  private final PushDeviceStore devices;
  private final ApnsSender sender;

  public PushDispatcher(
      NamedParameterJdbcTemplate jdbc,
      PlatformTransactionManager transactions,
      PushDeviceStore devices,
      ApnsSender sender) {
    this.jdbc = jdbc;
    this.transaction = new TransactionTemplate(transactions);
    this.devices = devices;
    this.sender = sender;
  }

  record Delivery(Notification notification, List<Device> devices) {}

  @Scheduled(
      initialDelayString = "${daisy.push.dispatch-initial-delay-ms:5000}",
      fixedDelayString = "${daisy.push.dispatch-delay-ms:5000}")
  public void tick() {
    try {
      dispatchOnce();
    } catch (RuntimeException e) {
      // 다음 주기에 다시 읽어요. 예외 메시지에는 SQL 값이 섞일 수 있어 형식 이름만 남겨요.
      LOG.warn("push_dispatch_failed type={}", e.getClass().getSimpleName());
    }
  }

  /** 한 주기를 돌려요. 보낸 시도 수를 돌려줘요. */
  int dispatchOnce() {
    List<Delivery> deliveries = Objects.requireNonNull(transaction.execute(status -> claim()));
    int attempts = 0;
    for (Delivery delivery : deliveries) {
      for (Device device : delivery.devices()) {
        deliver(delivery.notification(), device);
        attempts++;
      }
    }
    return attempts;
  }

  private List<Delivery> claim() {
    var cursorRows =
        jdbc.queryForList(
            "select last_id from push_cursor where name=:name for update",
            Map.of("name", CURSOR),
            Long.class);
    if (cursorRows.isEmpty()) {
      // 첫 실행: 지금 끝에서 시작해요. 쌓인 이벤트를 한꺼번에 보내지 않아요.
      jdbc.update(
          """
          insert into push_cursor(name,last_id,updated_at)
          select :name, coalesce(max(id),0), now() from deployment_log
          on conflict (name) do nothing
          """,
          Map.of("name", CURSOR));
      LOG.info("push_cursor_initialized");
      return List.of();
    }
    long cursor = cursorRows.getFirst();
    if (!sender.enabled()) {
      // 키가 없으면 보내지 않고 커서만 끝으로 옮겨요.
      jdbc.update(
          """
          update push_cursor set last_id=greatest(last_id,
            coalesce((select max(id) from deployment_log),0)), updated_at=now()
          where name=:name
          """,
          Map.of("name", CURSOR));
      return List.of();
    }
    Map<String, Object> bounds =
        jdbc.queryForMap(
            """
            select (select max(id) from deployment_log) as head,
              (select min(id) from deployment_log where id>:cursor
                and received_at > clock_timestamp() - interval '2 seconds') as unsettled
            """,
            Map.of("cursor", cursor));
    if (bounds.get("head") == null) return List.of();
    long safe =
        bounds.get("unsettled") != null
            ? ((Number) bounds.get("unsettled")).longValue() - 1
            : ((Number) bounds.get("head")).longValue();
    if (safe <= cursor) return List.of();
    List<EventRow> rows =
        jdbc.query(
            """
            select l.id,d.project_id,p.name as project_name,l.deployment_id,l.event_type,
              l.payload->>'status' as status,
              l.occurred_at < clock_timestamp() - interval '10 minutes' as stale
            from deployment_log l
            join deployment d on d.id=l.deployment_id
            join project p on p.id=d.project_id
            where l.id>:cursor and l.id<=:safe and l.processing_result='applied'
              and l.event_type in ('approval.required','deployment.completed')
            order by l.id limit
            """
                + BATCH,
            Map.of("cursor", cursor, "safe", safe),
            (rs, row) ->
                new EventRow(
                    new PushEvent(
                        rs.getLong("id"),
                        rs.getString("project_id"),
                        rs.getString("project_name"),
                        rs.getString("deployment_id"),
                        rs.getString("event_type"),
                        rs.getString("status")),
                    rs.getBoolean("stale")));
    long next = rows.size() == BATCH ? rows.getLast().event().id() : safe;
    jdbc.update(
        "update push_cursor set last_id=:next, updated_at=now() where name=:name",
        Map.of("next", next, "name", CURSOR));
    List<PushEvent> fresh = new ArrayList<>();
    for (EventRow row : rows) {
      if (row.stale()) LOG.info("push_skipped_stale event_id={}", row.event().id());
      else fresh.add(row.event());
    }
    Map<String, List<Device>> recipients = new HashMap<>();
    List<Delivery> deliveries = new ArrayList<>();
    for (Notification notification : PushMessages.plan(fresh)) {
      List<Device> targets =
          recipients.computeIfAbsent(notification.projectId(), devices::recipients);
      if (!targets.isEmpty()) deliveries.add(new Delivery(notification, targets));
    }
    return deliveries;
  }

  private record EventRow(PushEvent event, boolean stale) {}

  private void deliver(Notification notification, Device device) {
    Result result;
    try {
      result = sender.send(device, notification.collapseId(), notification.payloadJson());
    } catch (RuntimeException e) {
      result = new Result(0, e.getClass().getSimpleName());
    }
    if (result.ok()) {
      LOG.info(
          "push_sent kind={} deployment_id={} token_tail={}",
          notification.kind().code,
          notification.deploymentId(),
          device.tokenTail());
      return;
    }
    String reason = limit(result.reason() == null ? "status_" + result.status() : result.reason());
    if (result.deviceGone()) {
      try {
        devices.disable(device.apnsToken(), reason);
        LOG.info("push_device_disabled reason={} token_tail={}", reason, device.tokenTail());
      } catch (RuntimeException e) {
        LOG.warn(
            "push_device_disable_failed type={} token_tail={}",
            e.getClass().getSimpleName(),
            device.tokenTail());
      }
      return;
    }
    LOG.warn(
        "push_failed status={} reason={} deployment_id={} token_tail={}",
        result.status(),
        reason,
        notification.deploymentId(),
        device.tokenTail());
  }

  private static String limit(String value) {
    return value.length() <= 64 ? value : value.substring(0, 64);
  }
}
