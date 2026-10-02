package com.teamdaisy.server.project.application;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.teamdaisy.server.common.error.DaisyException;
import com.teamdaisy.server.common.error.ErrorCode;
import com.teamdaisy.server.identity.domain.Account;
import com.teamdaisy.server.identity.domain.AccountRepository;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.sql.Timestamp;
import java.time.Instant;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import org.springframework.jdbc.core.RowMapper;
import org.springframework.jdbc.core.namedparam.MapSqlParameterSource;
import org.springframework.jdbc.core.namedparam.NamedParameterJdbcTemplate;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;

/**
 * 배포 한 건의 스냅샷을 읽어요 (A-04).
 *
 * <p><b>배포 테이블을 읽기 전용 SQL 로 직접 읽어요.</b> {@code server/AGENTS.md} §3 의 예외(10/2 승환·은현 합의, #42)예요.
 * Entity· Repository 는 쓰지 않고 필요한 컬럼만 읽어요. 상태를 바꾸는 일은 하지 않아요 — 그건 실행 서비스만 해요.
 *
 * <p>권한은 호출하는 쪽이 {@code projectIdOf} 로 확인한 프로젝트 ID 를 넘겨요. 질의마다 그 프로젝트로 다시 걸러서 다른 프로젝트의 행이 섞이지 않게
 * 해요.
 */
@Component
@Transactional(readOnly = true)
public class DeploymentDetailReader {
  private final NamedParameterJdbcTemplate jdbc;
  private final AccountRepository accounts;
  private final ObjectMapper mapper;

  public DeploymentDetailReader(
      NamedParameterJdbcTemplate jdbc, AccountRepository accounts, ObjectMapper mapper) {
    this.jdbc = jdbc;
    this.accounts = accounts;
    this.mapper = mapper;
  }

  /** 배포 행이에요. 값은 DB 그대로이고, 공개 이름으로 바꾸는 일은 응답 쪽에서 해요. */
  public record DeploymentRow(
      String id,
      String projectId,
      String sourceVersionId,
      String commitSha,
      JsonNode imageRefs,
      String status,
      String kind,
      String rollbackOf,
      String retryOf,
      String createdBy,
      Instant createdAt,
      Instant finishedAt,
      long lastSeq) {}

  public record TargetRow(
      String targetId,
      JsonNode snapshot,
      String status,
      int attempt,
      boolean aiReused,
      String errorSummary,
      Instant cancelRequestedAt,
      Instant startedAt,
      Instant finishedAt,
      String step,
      String stepState,
      String approvalState,
      String applyDispatch,
      JsonNode result,
      List<StepDetails> steps,
      String healthState) {}

  /** 단계 이름별 가장 최근 시도의 관측이에요. durationMs는 단계 시간이지 HTTP 응답 시간이 아니에요. */
  public record StepDetails(
      String name,
      String state,
      @io.swagger.v3.oas.annotations.media.Schema(nullable = true) Long durationMs,
      @io.swagger.v3.oas.annotations.media.Schema(nullable = true) Instant startedAt) {}

  /** 대상의 지금 단계예요. 가장 최근 {@code step.*} 이벤트로 정해요. */
  record StepRow(String step, String state) {}

  public record PendingApproval(String targetId, String approvalId) {}

  public record DeploymentDetail(
      DeploymentRow deployment, List<TargetRow> targets, List<PendingApproval> pendingApprovals) {}

  private static final String DEPLOYMENT_COLUMNS =
      """
      select id, project_id, source_version_id, commit_sha, image_refs::text, status, kind,
             rollback_of_deployment_id, retry_of_deployment_id, requested_by,
             created_at, finished_at, last_event_seq
      from deployment
      """;

  /** 배포 한 건이에요 (A-04). 없거나 이 프로젝트 것이 아니면 404 예요. */
  public DeploymentDetail read(String projectId, String deploymentId) {
    List<DeploymentRow> found =
        jdbc.query(
            DEPLOYMENT_COLUMNS + " where id = :id and project_id = :project",
            Map.of("project", projectId, "id", deploymentId),
            deploymentMapper(new HashMap<>()));
    if (found.isEmpty()) {
      throw new DaisyException(ErrorCode.NOT_FOUND);
    }
    return withChildren(projectId, found).get(0);
  }

  /**
   * 배포 목록 한 페이지예요 (A-03). 최신순이고, {@code limit} 은 호출하는 쪽이 다듬어서 넘겨요.
   *
   * @param state 배포 전체 상태 하나. null 이면 전부예요
   * @param afterAt 커서의 생성 시각. null 이면 첫 페이지예요
   */
  public List<DeploymentDetail> list(
      String projectId, String state, Instant afterAt, String afterId, int limit) {
    StringBuilder where = new StringBuilder(" where project_id = :project");
    MapSqlParameterSource params =
        new MapSqlParameterSource().addValue("project", projectId).addValue("limit", limit);
    if (state != null) {
      where.append(" and status = :state");
      params.addValue("state", state);
    }
    if (afterAt != null) {
      // 같은 시각의 배포가 페이지 경계에 걸려도 건너뛰지 않게 (시각, ID) 로 이어요.
      where.append(" and (created_at < :at or (created_at = :at and id < :id))");
      params.addValue("at", Timestamp.from(afterAt)).addValue("id", afterId);
    }
    List<DeploymentRow> page =
        jdbc.query(
            DEPLOYMENT_COLUMNS + where + " order by created_at desc, id desc limit :limit",
            params,
            deploymentMapper(new HashMap<>()));
    return withChildren(projectId, page);
  }

  /** 한 페이지의 대상·승인 대기를 배포 ID 로 한 번씩만 읽어서 붙여요. 배포마다 따로 읽지 않아요. */
  private List<DeploymentDetail> withChildren(String projectId, List<DeploymentRow> rows) {
    if (rows.isEmpty()) {
      return List.of();
    }
    MapSqlParameterSource params =
        new MapSqlParameterSource()
            .addValue("project", projectId)
            .addValue("ids", rows.stream().map(DeploymentRow::id).toList());
    // occurrence 시작 순서를 먼저 봐서 늦게 끝난 이전 시도가 새 시도를 덮지 않게 해요.
    Map<String, StepRow> steps = new HashMap<>();
    Map<String, Long> latestStepSequences = new HashMap<>();
    Map<String, List<StepDetails>> stepDetails = new HashMap<>();
    Map<String, String> healthStates = new HashMap<>();
    jdbc.query(
        """
        with observed as (
          select e.*, je.created_at as execution_created_at, dt.current_execution_id, je.operation,
                 max(e.source_sequence) filter (where e.event_type = 'step.started') over (
                   partition by e.deployment_target_id, e.execution_id, e.step, e.stage_occurrence_id
                 ) as occurrence_sequence
          from deployment_log e
          join deployment_target dt on dt.id = e.deployment_target_id
          left join jenkins_execution je on je.id = e.execution_id
          where dt.deployment_id in (:ids) and dt.project_id = :project
            and e.event_type in ('step.started', 'step.completed', 'step.failed')
            and e.processing_result = 'applied'
            and (e.step not in ('apply', 'health_check')
                 or dt.current_execution_id is null
                 or (e.execution_id = dt.current_execution_id and je.operation = 'apply'))
        )
        select distinct on (deployment_target_id, step)
               deployment_target_id, step, event_type, occurred_at, execution_id, current_execution_id,
               operation, seq,
               (payload->>'duration_ms')::bigint as duration_ms,
               (payload->>'started_at')::timestamptz as stage_started_at
        from observed
        order by deployment_target_id, step, execution_created_at desc nulls last,
                 coalesce(occurrence_sequence, source_sequence, seq) desc,
                 coalesce(source_sequence, seq) desc, seq desc
        """,
        params,
        (ResultSet rs) -> {
          String id = rs.getString("deployment_target_id");
          String name = rs.getString("step");
          String state = stepState(rs.getString("event_type"));
          String currentExecution = rs.getString("current_execution_id");
          boolean current =
              currentExecution != null && currentExecution.equals(rs.getString("execution_id"));
          long seq = rs.getLong("seq");
          if ((current || currentExecution == null)
              && seq > latestStepSequences.getOrDefault(id, 0L)) {
            steps.put(id, new StepRow(name, state));
            latestStepSequences.put(id, seq);
          }
          stepDetails
              .computeIfAbsent(id, key -> new ArrayList<>())
              .add(
                  new StepDetails(
                      name,
                      state,
                      (Long) rs.getObject("duration_ms"),
                      "running".equals(state)
                          ? instant(rs, "occurred_at")
                          : instant(rs, "stage_started_at")));
          if (current && "apply".equals(rs.getString("operation")) && "health_check".equals(name)) {
            healthStates.put(
                id,
                "done".equals(state)
                    ? "healthy"
                    : "failed".equals(state) ? "unhealthy" : "unknown");
          }
        });
    List<String> order =
        List.of("generate", "validate", "plan", "risk_check", "apply", "health_check");
    stepDetails.replaceAll(
        (id, values) ->
            values.stream()
                .sorted(Comparator.comparingInt(value -> order.indexOf(value.name())))
                .toList());
    Map<String, List<TargetRow>> targets = new HashMap<>();
    jdbc.query(
        """
        select dt.id, dt.deployment_id, dt.target_id, dt.target_snapshot::text, dt.status,
               dt.attempt, dt.ai_reused, dt.error_summary, dt.cancel_requested_at,
               dt.started_at, dt.finished_at, dt.result::text,
               a.state as approval_state, je.operation, je.dispatch_status
        from deployment_target dt
        left join approval a on a.plan_id = dt.current_plan_id and a.deployment_target_id = dt.id
        left join jenkins_execution je on je.id = dt.current_execution_id
        where dt.deployment_id in (:ids) and dt.project_id = :project
        order by dt.deployment_id, dt.target_id
        """,
        params,
        (ResultSet rs) -> {
          targets
              .computeIfAbsent(rs.getString("deployment_id"), key -> new ArrayList<>())
              .add(
                  new TargetRow(
                      rs.getString("target_id"),
                      json(rs.getString("target_snapshot")),
                      rs.getString("status"),
                      rs.getInt("attempt"),
                      rs.getBoolean("ai_reused"),
                      rs.getString("error_summary"),
                      instant(rs, "cancel_requested_at"),
                      instant(rs, "started_at"),
                      instant(rs, "finished_at"),
                      step(steps, rs.getString("id")).step(),
                      step(steps, rs.getString("id")).state(),
                      rs.getString("approval_state"),
                      applyDispatch(rs.getString("operation"), rs.getString("dispatch_status")),
                      json(rs.getString("result")),
                      stepDetails.getOrDefault(rs.getString("id"), List.of()),
                      healthStates.getOrDefault(rs.getString("id"), "unknown")));
        });
    // 만료 시각이 지난 승인은 아직 pending 으로 남아 있어도 빼요. 보내 봐야 옛 승인이라 409 예요.
    Map<String, List<PendingApproval>> pending = new HashMap<>();
    jdbc.query(
        """
        select dt.deployment_id, dt.target_id, a.id
        from approval a
        join deployment_target dt on dt.id = a.deployment_target_id
        where dt.deployment_id in (:ids) and dt.project_id = :project
          and a.state = 'pending' and a.expires_at > now()
        order by dt.deployment_id, dt.target_id
        """,
        params,
        (ResultSet rs) -> {
          pending
              .computeIfAbsent(rs.getString("deployment_id"), key -> new ArrayList<>())
              .add(new PendingApproval(rs.getString("target_id"), rs.getString("id")));
        });
    return rows.stream()
        .map(
            row ->
                new DeploymentDetail(
                    row,
                    List.copyOf(targets.getOrDefault(row.id(), List.of())),
                    List.copyOf(pending.getOrDefault(row.id(), List.of()))))
        .toList();
  }

  private static final StepRow NO_STEP = new StepRow(null, null);

  private static StepRow step(Map<String, StepRow> steps, String deploymentTargetId) {
    return steps.getOrDefault(deploymentTargetId, NO_STEP);
  }

  /** 이벤트 종류를 소비자 값으로 바꿔요. {@code waiting} 은 근거 이벤트가 없어 만들지 않아요. */
  public static String stepState(String eventType) {
    return switch (eventType) {
      case "step.started" -> "running";
      case "step.completed" -> "done";
      case "step.failed" -> "failed";
      default -> null;
    };
  }

  /**
   * 대상의 현재 명령이 apply 일 때만 제출 상태를 화면 값으로 묶어요 (#42 승환님 제안).
   *
   * <p>제출 전·제출 중·접수됨은 queued, 제출 결과를 모르면 unknown, 거절되면 rejected 예요. apply 가 아니면 null 이에요.
   */
  public static String applyDispatch(String operation, String dispatchStatus) {
    if (!"apply".equals(operation) || dispatchStatus == null) {
      return null;
    }
    return switch (dispatchStatus) {
      case "pending", "dispatching", "accepted" -> "queued";
      case "unknown" -> "unknown";
      case "rejected" -> "rejected";
      default -> null;
    };
  }

  /** 요청자 표시 이름은 한 요청 안에서 계정마다 한 번만 읽어요. */
  private RowMapper<DeploymentRow> deploymentMapper(Map<String, String> names) {
    return (rs, row) ->
        new DeploymentRow(
            rs.getString("id"),
            rs.getString("project_id"),
            rs.getString("source_version_id"),
            rs.getString("commit_sha"),
            json(rs.getString("image_refs")),
            rs.getString("status"),
            rs.getString("kind"),
            rs.getString("rollback_of_deployment_id"),
            rs.getString("retry_of_deployment_id"),
            names.computeIfAbsent(rs.getString("requested_by"), this::displayName),
            instant(rs, "created_at"),
            instant(rs, "finished_at"),
            rs.getLong("last_event_seq"));
  }

  /** 요청자는 계정 표시 이름으로 보여줘요. 계정이 없으면 ID 그대로예요. */
  private String displayName(String accountId) {
    if (accountId == null) {
      return null;
    }
    return accounts.findById(accountId).map(Account::displayName).orElse(accountId);
  }

  private JsonNode json(String value) {
    if (value == null) {
      return null;
    }
    try {
      return mapper.readTree(value);
    } catch (JsonProcessingException exception) {
      // 저장된 JSON 이 깨졌으면 그 필드만 비워요. 상세 화면 전체를 실패시키지 않아요.
      return null;
    }
  }

  private static Instant instant(ResultSet rs, String column) throws SQLException {
    Timestamp value = rs.getTimestamp(column);
    return value == null ? null : value.toInstant();
  }
}
