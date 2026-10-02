package com.teamdaisy.server.project.application;

import java.sql.Timestamp;
import java.time.Instant;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.Map;
import org.springframework.jdbc.core.namedparam.MapSqlParameterSource;
import org.springframework.jdbc.core.namedparam.NamedParameterJdbcTemplate;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;

/**
 * 배포의 최근 로그를 읽어요 (A-07).
 *
 * <p><b>{@code deployment_log} 를 읽기 전용 SQL 로 직접 읽어요.</b> {@code server/AGENTS.md} §3 의 예외예요. 쓰는 쪽은
 * 승환의 Jenkins 수신이고, 메시지는 저장할 때 {@code EventJournal.validate} 가 비밀값 패턴을 막아요. 그래서 읽을 때 따로 가리지 않아요.
 */
@Component
@Transactional(readOnly = true)
public class DeploymentLogReader {
  private final NamedParameterJdbcTemplate jdbc;

  public DeploymentLogReader(NamedParameterJdbcTemplate jdbc) {
    this.jdbc = jdbc;
  }

  /**
   * 로그 한 행이에요.
   *
   * @param targetId 실행 전체 콘솔 로그면 null
   */
  public record LogRow(
      long seq, Instant at, String targetId, String step, String level, String message) {}

  /** 이 배포에 그 대상이 있는지 봐요. */
  public boolean hasTarget(String projectId, String deploymentId, String targetId) {
    Integer count =
        jdbc.queryForObject(
            """
            select count(*) from deployment_target
            where deployment_id = :deployment and project_id = :project and target_id = :target
            """,
            Map.of("project", projectId, "deployment", deploymentId, "target", targetId),
            Integer.class);
    return count != null && count > 0;
  }

  /**
   * 최근 로그 {@code limit} 개를 오래된 것부터 돌려줘요.
   *
   * <p>{@code targetId} 를 주면 그 대상 행과, 그 대상을 포함한 실행의 대상 없는 콘솔 행을 같이 줘요. Jenkins 콘솔은 실행 단위라 대상별로 나뉘지
   * 않아요.
   */
  public List<LogRow> tail(String projectId, String deploymentId, String targetId, int limit) {
    StringBuilder sql =
        new StringBuilder(
            """
            select e.seq, e.occurred_at, t.target_id, e.step, e.level, e.message
            from deployment_log e
            join deployment d on d.id = e.deployment_id
            left join deployment_target t on t.id = e.deployment_target_id
            where e.deployment_id = :deployment and d.project_id = :project
              and e.event_type = 'log.batch'
            """);
    MapSqlParameterSource params =
        new MapSqlParameterSource()
            .addValue("project", projectId)
            .addValue("deployment", deploymentId)
            .addValue("limit", limit);
    if (targetId != null) {
      sql.append(
          """
            and (t.target_id = :target
                 or (e.deployment_target_id is null and e.execution_id in (
                       select et.execution_id from execution_target et
                       join deployment_target dt on dt.id = et.deployment_target_id
                       where dt.deployment_id = :deployment and dt.target_id = :target)))
          """);
      params.addValue("target", targetId);
    }
    sql.append(" order by e.seq desc limit :limit");
    List<LogRow> rows =
        new ArrayList<>(
            jdbc.query(
                sql.toString(),
                params,
                (rs, row) ->
                    new LogRow(
                        rs.getLong("seq"),
                        instant(rs.getTimestamp("occurred_at")),
                        rs.getString("target_id"),
                        rs.getString("step"),
                        rs.getString("level"),
                        rs.getString("message"))));
    Collections.reverse(rows);
    return rows;
  }

  private static Instant instant(Timestamp value) {
    return value == null ? null : value.toInstant();
  }
}
