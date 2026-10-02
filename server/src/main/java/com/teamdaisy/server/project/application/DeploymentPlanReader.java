package com.teamdaisy.server.project.application;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.math.BigDecimal;
import java.util.List;
import java.util.Map;
import org.springframework.jdbc.core.namedparam.NamedParameterJdbcTemplate;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;

/**
 * 배포의 현재 plan 과 AI 사용량 합계를 읽어요 (A-05·WR-06).
 *
 * <p><b>{@code plan_revision}·{@code ai_usage} 를 읽기 전용 SQL 로 직접 읽어요.</b> {@code server/AGENTS.md}
 * §3 의 예외(10/2 승환·은현 합의, #42)예요. 상태는 바꾸지 않아요.
 *
 * <p>권한은 호출하는 쪽이 {@code projectIdOf} 로 확인한 프로젝트 ID 를 넘겨요. 질의마다 그 프로젝트로 다시 걸러요.
 */
@Component
@Transactional(readOnly = true)
public class DeploymentPlanReader {
  private final NamedParameterJdbcTemplate jdbc;
  private final ObjectMapper mapper;

  public DeploymentPlanReader(NamedParameterJdbcTemplate jdbc, ObjectMapper mapper) {
    this.jdbc = jdbc;
    this.mapper = mapper;
  }

  /** 대상 하나의 현재 plan 이에요. 값은 DB 그대로이고, 공개 모양으로 바꾸는 일은 응답 쪽에서 해요. */
  public record PlanRow(String targetId, JsonNode summary, JsonNode resources) {}

  /**
   * AI 사용량 합계예요.
   *
   * @param tokens 입력·출력 토큰을 둘 다 아는 행의 합. 그런 행이 없으면 null
   * @param costUsd 비용을 아는 행의 USD 합. 그런 행이 없으면 null
   * @param unknownCalls 토큰이나 비용을 모르는 행 수
   */
  public record UsageTotals(long calls, long unknownCalls, Long tokens, BigDecimal costUsd) {}

  /** 현재 plan 이 있는 대상만 {@code target_id} 순으로 돌려줘요. plan 전이거나 바뀌는 중인 대상은 빠져요. */
  public List<PlanRow> currentPlans(String projectId, String deploymentId) {
    return jdbc.query(
        """
        select dt.target_id, p.summary::text as summary, p.resources::text as resources
        from deployment_target dt
        join plan_revision p on p.id = dt.current_plan_id and p.deployment_target_id = dt.id
        where dt.deployment_id = :deployment and dt.project_id = :project
        order by dt.target_id
        """,
        Map.of("project", projectId, "deployment", deploymentId),
        (rs, row) ->
            new PlanRow(
                rs.getString("target_id"),
                json(rs.getString("summary")),
                json(rs.getString("resources"))));
  }

  /** 이 배포의 모든 대상·회차의 사용량을 더해요. 행이 없으면 {@code calls} 0, 토큰·비용 null 이에요. */
  public UsageTotals usage(String projectId, String deploymentId) {
    // null + 숫자는 null 이라, 토큰 하나라도 모르는 행은 sum 에서 빠져요.
    return jdbc.queryForObject(
        """
        select count(*) as calls,
               count(*) filter (where u.input_tokens is null or u.output_tokens is null
                                   or u.cost_usd is null) as unknown_calls,
               sum(u.input_tokens + u.output_tokens) as tokens,
               sum(u.cost_usd) as cost_usd
        from ai_usage u
        join deployment_target dt on dt.id = u.deployment_target_id
        where dt.deployment_id = :deployment and dt.project_id = :project
        """,
        Map.of("project", projectId, "deployment", deploymentId),
        (rs, row) -> {
          long tokens = rs.getLong("tokens");
          Long knownTokens = rs.wasNull() ? null : tokens;
          return new UsageTotals(
              rs.getLong("calls"),
              rs.getLong("unknown_calls"),
              knownTokens,
              rs.getBigDecimal("cost_usd"));
        });
  }

  private JsonNode json(String value) {
    if (value == null) {
      return null;
    }
    try {
      return mapper.readTree(value);
    } catch (JsonProcessingException exception) {
      // 저장된 JSON 이 깨졌으면 그 필드만 비워요. 화면 전체를 실패시키지 않아요.
      return null;
    }
  }
}
