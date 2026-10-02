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
import java.util.List;
import java.util.Map;
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
      Instant finishedAt) {}

  public record PendingApproval(String targetId, String approvalId) {}

  public record DeploymentDetail(
      DeploymentRow deployment, List<TargetRow> targets, List<PendingApproval> pendingApprovals) {}

  public DeploymentDetail read(String projectId, String deploymentId) {
    Map<String, String> params = Map.of("project", projectId, "id", deploymentId);
    List<DeploymentRow> found =
        jdbc.query(
            """
            select id, project_id, source_version_id, commit_sha, image_refs::text, status, kind,
                   rollback_of_deployment_id, retry_of_deployment_id, requested_by,
                   created_at, finished_at, last_event_seq
            from deployment
            where id = :id and project_id = :project
            """,
            params,
            (rs, row) ->
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
                    displayName(rs.getString("requested_by")),
                    instant(rs, "created_at"),
                    instant(rs, "finished_at"),
                    rs.getLong("last_event_seq")));
    if (found.isEmpty()) {
      throw new DaisyException(ErrorCode.NOT_FOUND);
    }
    List<TargetRow> targets =
        jdbc.query(
            """
            select target_id, target_snapshot::text, status, attempt, ai_reused, error_summary,
                   cancel_requested_at, started_at, finished_at
            from deployment_target
            where deployment_id = :id and project_id = :project
            order by target_id
            """,
            params,
            (rs, row) ->
                new TargetRow(
                    rs.getString("target_id"),
                    json(rs.getString("target_snapshot")),
                    rs.getString("status"),
                    rs.getInt("attempt"),
                    rs.getBoolean("ai_reused"),
                    rs.getString("error_summary"),
                    instant(rs, "cancel_requested_at"),
                    instant(rs, "started_at"),
                    instant(rs, "finished_at")));
    // 만료 시각이 지난 승인은 아직 pending 으로 남아 있어도 빼요. 보내 봐야 옛 승인이라 409 예요.
    List<PendingApproval> pending =
        jdbc.query(
            """
            select dt.target_id, a.id
            from approval a
            join deployment_target dt on dt.id = a.deployment_target_id
            where dt.deployment_id = :id and dt.project_id = :project
              and a.state = 'pending' and a.expires_at > now()
            order by dt.target_id
            """,
            params,
            (rs, row) -> new PendingApproval(rs.getString("target_id"), rs.getString("id")));
    return new DeploymentDetail(found.get(0), targets, pending);
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
