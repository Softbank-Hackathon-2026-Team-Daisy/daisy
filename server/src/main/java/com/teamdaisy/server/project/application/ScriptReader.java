package com.teamdaisy.server.project.application;

import java.sql.ResultSet;
import java.sql.SQLException;
import java.sql.Timestamp;
import java.time.Instant;
import java.util.List;
import java.util.Map;
import org.springframework.jdbc.core.namedparam.MapSqlParameterSource;
import org.springframework.jdbc.core.namedparam.NamedParameterJdbcTemplate;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;

/**
 * 프로젝트의 검증된 스크립트 목록을 읽어요 (WR-10).
 *
 * <p><b>{@code script}·{@code deployment_target}·{@code plan_revision} 을 읽기 전용 SQL 로 직접 읽어요.</b> 설계
 * 5.12 "script — 승환 수집, 은현 조회" 이고 {@code server/AGENTS.md} §3 예외예요. 파일 내용은 서버가 갖고 있지 않아요 (WR-07).
 */
@Component
@Transactional(readOnly = true)
public class ScriptReader {
  /** 대상당 버전이 몇 개라 한 번에 줘요. 넘칠 때만 여기서 잘라요. */
  public static final int MAX_ROWS = 500;

  private final NamedParameterJdbcTemplate jdbc;

  public ScriptReader(NamedParameterJdbcTemplate jdbc) {
    this.jdbc = jdbc;
  }

  /**
   * 스크립트 한 줄이에요. 값은 DB 그대로이고 공개 모양으로 바꾸는 일은 응답 쪽에서 해요.
   *
   * @param sourceReused 처음 검증한 대상이 재사용이었는지. 그 대상이 없으면 null
   * @param sourceAttempt 처음 검증한 대상의 시도 횟수. 그 대상이 없으면 null
   * @param planCount 이 스크립트로 만든 plan 수
   * @param latestRisks 가장 최근 plan 의 위험 설정 수. plan 이 없으면 null
   */
  public record ScriptRow(
      String id,
      String targetId,
      String environmentType,
      int version,
      Instant validatedAt,
      Instant unavailableAt,
      Instant artifactExpiresAt,
      Boolean sourceReused,
      Integer sourceAttempt,
      long reuseCount,
      Instant lastUsedAt,
      long planCount,
      Integer latestRisks) {}

  /** 이 프로젝트의 대상인지 봐요. */
  public boolean hasTarget(String projectId, String targetId) {
    Integer count =
        jdbc.queryForObject(
            "select count(*) from target where id = :target and project_id = :project",
            Map.of("project", projectId, "target", targetId),
            Integer.class);
    return count != null && count > 0;
  }

  /** 대상 순, 버전 내림차순이에요. {@code targetId} 가 null 이면 프로젝트 전체예요. */
  public List<ScriptRow> list(String projectId, String targetId) {
    StringBuilder sql =
        new StringBuilder(
            """
            select s.id, s.target_id, t.environment_type, s.version, s.validated_at,
                   s.unavailable_at, s.artifact_expires_at,
                   src.ai_reused as source_reused, src.attempt as source_attempt,
                   (select count(*) from deployment_target u
                     where u.script_id = s.id and u.project_id = s.project_id and u.ai_reused
                       and u.status = 'succeeded')
                     as reuse_count,
                   (select max(coalesce(u.finished_at, u.started_at)) from deployment_target u
                     where u.script_id = s.id and u.project_id = s.project_id) as last_used_at,
                   (select count(*) from plan_revision p where p.script_id = s.id) as plan_count,
                   (select case when jsonb_typeof(p.summary -> 'risks') = 'array'
                                then jsonb_array_length(p.summary -> 'risks') end
                      from plan_revision p where p.script_id = s.id
                      order by p.created_at desc, p.id desc limit 1) as latest_risks
            from script s
            join target t on t.id = s.target_id and t.project_id = s.project_id
            left join deployment_target src on src.id = s.source_deployment_target_id
            where s.project_id = :project
            """);
    MapSqlParameterSource params =
        new MapSqlParameterSource().addValue("project", projectId).addValue("limit", MAX_ROWS);
    if (targetId != null) {
      sql.append(" and s.target_id = :target");
      params.addValue("target", targetId);
    }
    sql.append(" order by s.target_id, s.version desc limit :limit");
    return jdbc.query(sql.toString(), params, (rs, row) -> row(rs));
  }

  private static ScriptRow row(ResultSet rs) throws SQLException {
    boolean reused = rs.getBoolean("source_reused");
    Boolean sourceReused = rs.wasNull() ? null : reused;
    int attempt = rs.getInt("source_attempt");
    Integer sourceAttempt = rs.wasNull() ? null : attempt;
    int risks = rs.getInt("latest_risks");
    Integer latestRisks = rs.wasNull() ? null : risks;
    return new ScriptRow(
        rs.getString("id"),
        rs.getString("target_id"),
        rs.getString("environment_type"),
        rs.getInt("version"),
        instant(rs.getTimestamp("validated_at")),
        instant(rs.getTimestamp("unavailable_at")),
        instant(rs.getTimestamp("artifact_expires_at")),
        sourceReused,
        sourceAttempt,
        rs.getLong("reuse_count"),
        instant(rs.getTimestamp("last_used_at")),
        rs.getLong("plan_count"),
        latestRisks);
  }

  private static Instant instant(Timestamp value) {
    return value == null ? null : value.toInstant();
  }
}
