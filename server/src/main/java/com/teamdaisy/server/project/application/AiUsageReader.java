package com.teamdaisy.server.project.application;

import java.math.BigDecimal;
import java.sql.Timestamp;
import java.time.Instant;
import java.util.List;
import java.util.Map;
import org.springframework.jdbc.core.namedparam.NamedParameterJdbcTemplate;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;

/**
 * 배포 한 건의 AI 호출 기록을 읽어요 (WR-11). 합계는 A-05 가 맡아요.
 *
 * <p><b>{@code ai_usage} 를 읽기 전용 SQL 로 직접 읽어요.</b> {@code server/AGENTS.md} §3 예외예요. 쓰는 쪽은 승환의
 * 수신부예요. 지금 Jenkins 는 호출별 기록을 주지 않아서 대부분 빈 목록이에요.
 */
@Component
@Transactional(readOnly = true)
public class AiUsageReader {
  /** 한 배포의 호출은 대상당 많아야 몇 번이라 한 번에 줘요. 넘칠 때만 여기서 잘라요. */
  public static final int MAX_ROWS = 1000;

  private final NamedParameterJdbcTemplate jdbc;

  public AiUsageReader(NamedParameterJdbcTemplate jdbc) {
    this.jdbc = jdbc;
  }

  /**
   * 호출 한 번이에요. 값은 DB 그대로예요.
   *
   * @param tokens 입력·출력 토큰을 둘 다 알면 합, 아니면 null
   */
  public record CallRow(
      Instant at,
      String deploymentId,
      String targetId,
      String step,
      int attempt,
      Long tokens,
      BigDecimal costUsd,
      String status) {}

  /** 이 프로젝트의 배포인지 봐요. */
  public boolean hasDeployment(String projectId, String deploymentId) {
    Integer count =
        jdbc.queryForObject(
            "select count(*) from deployment where id = :deployment and project_id = :project",
            Map.of("project", projectId, "deployment", deploymentId),
            Integer.class);
    return count != null && count > 0;
  }

  /** 호출 시각 순, 같은 시각이면 ID 순이에요. */
  public List<CallRow> calls(String projectId, String deploymentId) {
    return jdbc.query(
        """
        select u.occurred_at, dt.deployment_id, dt.target_id, u.step, u.attempt,
               u.input_tokens + u.output_tokens as tokens, u.cost_usd, u.status
        from ai_usage u
        join deployment_target dt on dt.id = u.deployment_target_id
        where dt.deployment_id = :deployment and dt.project_id = :project
        order by u.occurred_at, u.id
        limit :limit
        """,
        Map.of("project", projectId, "deployment", deploymentId, "limit", MAX_ROWS),
        (rs, row) -> {
          long tokens = rs.getLong("tokens");
          Long known = rs.wasNull() ? null : tokens;
          Timestamp at = rs.getTimestamp("occurred_at");
          return new CallRow(
              at == null ? null : at.toInstant(),
              rs.getString("deployment_id"),
              rs.getString("target_id"),
              rs.getString("step"),
              rs.getInt("attempt"),
              known,
              rs.getBigDecimal("cost_usd"),
              rs.getString("status"));
        });
  }
}
