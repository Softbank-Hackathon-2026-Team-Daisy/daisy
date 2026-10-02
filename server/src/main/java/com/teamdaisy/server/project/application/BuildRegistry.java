package com.teamdaisy.server.project.application;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.teamdaisy.server.common.error.DaisyException;
import com.teamdaisy.server.common.error.ErrorCode;
import com.teamdaisy.server.project.domain.ImageRefs;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.sql.Timestamp;
import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.UUID;
import java.util.regex.Pattern;
import org.springframework.jdbc.core.namedparam.MapSqlParameterSource;
import org.springframework.jdbc.core.namedparam.NamedParameterJdbcTemplate;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;

/**
 * Jenkins CI 빌드 결과를 {@code source_version} 에 저장해요 (#42 ④, 10/2 승환님 답).
 *
 * <p>공개 API 가 아니라 승환님 Jenkins 수신부가 부르는 서비스예요. 수신부가 그 실행이 등록된 프로젝트·저장소와 맞는지 확인한 뒤 부르고, 같은 트랜잭션에서
 * {@code build.received} 이벤트를 남겨요. 그래서 여기서는 트랜잭션을 따로 열지 않아요 ({@code REQUIRES_NEW} 없음).
 *
 * <p>같은 {@code (source, external_build_id)} 는 한 행이에요. 상태는 건너뛰어도 되지만 뒤로 가지 않고, 종료 결과는 바뀌지 않아요. 규칙 표는
 * {@code server/SPEC.md} 「빌드 결과 저장」 이에요.
 */
@Component
public class BuildRegistry {
  private static final Pattern COMMIT = Pattern.compile("[0-9a-f]{40}|[0-9a-f]{64}");
  private static final List<String> ORDER = List.of("pending", "running", "succeeded", "failed");
  private static final String SUCCEEDED = "succeeded";
  private static final int MAX_KEY = 255;
  private static final int MAX_URL = 2048;
  private static final int MAX_ERROR = 4000;

  private final NamedParameterJdbcTemplate jdbc;
  private final ObjectMapper mapper;

  public BuildRegistry(NamedParameterJdbcTemplate jdbc, ObjectMapper mapper) {
    this.jdbc = jdbc;
    this.mapper = mapper;
  }

  /**
   * Jenkins 가 알려 준 빌드 하나예요.
   *
   * @param source Jenkins 인스턴스처럼 빌드 ID 를 발급한 범위
   * @param externalBuildId 그 범위 안에서 빌드를 구분하는 ID (예: 전체 Job 경로 + 빌드 번호)
   * @param status {@code pending}·{@code running}·{@code succeeded}·{@code failed}
   * @param imageRefs {@code succeeded} 일 때만, 계약 모양 {@code {service: {image_ref, digest?,
   *     commit_sha}}}
   */
  public record BuildReport(
      String projectId,
      String source,
      String externalBuildId,
      String commitSha,
      String branch,
      String status,
      JsonNode imageRefs,
      String runUrl,
      Instant startedAt,
      Instant finishedAt,
      String errorSummary) {}

  /**
   * 저장 결과예요.
   *
   * @param changed 행이 새로 생기거나 바뀌었으면 true. false 면 수신부는 이벤트를 다시 남기지 않아요
   * @param statusChanged 새 빌드이거나 상태가 앞으로 갔으면 true. 같은 상태에서 빈 값만 채웠으면 false 예요. 이벤트는 이 값으로 남겨요
   */
  public record Recorded(String sourceVersionId, boolean changed, boolean statusChanged) {}

  /** 저장된 행에서 판단에 필요한 값이에요. */
  record Stored(
      String id,
      String projectId,
      String commitSha,
      String branch,
      String status,
      JsonNode imageRefs,
      String runUrl,
      Instant startedAt,
      Instant finishedAt,
      String errorSummary) {}

  /** 같은 키가 이미 있을 때 할 일이에요. */
  enum Outcome {
    UNCHANGED,
    ADVANCE,
    FILL
  }

  @Transactional
  public Recorded record(BuildReport input) {
    BuildReport report = validate(input);
    // 저장하기 전에 활성 프로젝트 행을 먼저 잠가요. 실행부와 같은 project → source_version → event 순서예요.
    // 잠그지 않으면 같은 프로젝트의 다른 빌드 둘이 동시에 올 때, 각 INSERT 의 FK 검사가 project 에 KEY SHARE 를 남기고
    // 뒤이은 이벤트 기록이 둘 다 같은 project 를 FOR UPDATE 로 올리려다 교착돼요 (#72 리뷰).
    List<String> active =
        jdbc.queryForList(
            "select id from project where id = :project and archived_at is null for update",
            Map.of("project", report.projectId()),
            String.class);
    if (active.isEmpty()) {
      throw new DaisyException(ErrorCode.NOT_FOUND);
    }
    String id = "sv_" + UUID.randomUUID();
    // 동시에 같은 키가 와도 예외 없이 한 행으로 모이게 해요. 늦은 쪽은 먼저 넣은 쪽 커밋을 기다렸다가 아무것도 넣지 않아요.
    int inserted =
        jdbc.update(
            """
            insert into source_version(id, project_id, source, external_build_id, commit_sha, branch,
                                       status, image_refs, run_url, started_at, finished_at,
                                       error_summary)
            values (:id, :project, :source, :external, :commit, :branch, :status,
                    cast(:images as jsonb), :run, :started, :finished, :error)
            on conflict (source, external_build_id) do nothing
            """,
            params(report).addValue("id", id));
    if (inserted == 1) {
      return new Recorded(id, true, true);
    }
    Stored stored =
        jdbc.queryForObject(
            """
            select id, project_id, commit_sha, branch, status, image_refs::text as image_refs,
                   run_url, started_at, finished_at, error_summary
            from source_version
            where source = :source and external_build_id = :external
            for update
            """,
            params(report),
            (rs, row) -> stored(rs));
    Outcome outcome = decide(stored, report);
    if (outcome == Outcome.ADVANCE) {
      jdbc.update(
          """
          update source_version
          set status = :status, image_refs = cast(:images as jsonb),
              branch = coalesce(branch, :branch), run_url = coalesce(:run, run_url),
              started_at = coalesce(started_at, :started), finished_at = :finished,
              error_summary = :error
          where id = :id
          """,
          params(report).addValue("id", stored.id()));
    } else if (outcome == Outcome.FILL) {
      jdbc.update(
          """
          update source_version
          set branch = coalesce(branch, :branch), run_url = coalesce(run_url, :run),
              started_at = coalesce(started_at, :started)
          where id = :id
          """,
          params(report).addValue("id", stored.id()));
    }
    return new Recorded(stored.id(), outcome != Outcome.UNCHANGED, outcome == Outcome.ADVANCE);
  }

  /**
   * 같은 키가 이미 있을 때 무엇을 할지 정해요. 충돌이면 409 를 던져요.
   *
   * <p>상태 순서는 pending → running → 종료(succeeded·failed) 예요. 뒤로 가는 보고는 폴링이 늦게 본 옛 상태라 무시해요. 종료 결과가 서로
   * 다르면 어느 쪽도 믿을 수 없어서 덮어쓰지 않고 거절해요.
   */
  static Outcome decide(Stored stored, BuildReport report) {
    if (!stored.projectId().equals(report.projectId())
        || !stored.commitSha().equals(report.commitSha())
        || (stored.branch() != null
            && report.branch() != null
            && !stored.branch().equals(report.branch()))) {
      throw conflict();
    }
    int before = rank(stored.status());
    int after = rank(report.status());
    if (after < before) {
      return Outcome.UNCHANGED;
    }
    if (after > before) {
      return Outcome.ADVANCE;
    }
    if (terminal(stored.status())) {
      if (!stored.status().equals(report.status())
          || !Objects.equals(stored.imageRefs(), report.imageRefs())
          || !Objects.equals(stored.finishedAt(), report.finishedAt())
          || !Objects.equals(stored.errorSummary(), report.errorSummary())) {
        throw conflict();
      }
      return Outcome.UNCHANGED;
    }
    boolean fills =
        (stored.runUrl() == null && report.runUrl() != null)
            || (stored.startedAt() == null && report.startedAt() != null)
            || (stored.branch() == null && report.branch() != null);
    return fills ? Outcome.FILL : Outcome.UNCHANGED;
  }

  /** 모양을 보고, 시각은 DB 정밀도(마이크로초)로 맞춰요. 같은 보고를 다시 받았을 때 나노초 차이로 충돌이 나지 않게 해요. */
  static BuildReport validate(BuildReport report) {
    if (report == null
        || blank(report.projectId())
        || blank(report.source())
        || report.source().length() > MAX_KEY
        || blank(report.externalBuildId())
        || report.externalBuildId().length() > MAX_KEY
        || report.commitSha() == null
        || !COMMIT.matcher(report.commitSha()).matches()
        || report.status() == null
        || !ORDER.contains(report.status())
        || (report.branch() != null
            && (report.branch().isBlank() || report.branch().length() > MAX_KEY))
        || (report.runUrl() != null && report.runUrl().length() > MAX_URL)
        || (report.errorSummary() != null && report.errorSummary().length() > MAX_ERROR)) {
      throw invalid();
    }
    boolean succeeded = SUCCEEDED.equals(report.status());
    boolean hasImages = report.imageRefs() != null && !report.imageRefs().isNull();
    if (succeeded != hasImages
        || (succeeded && !ImageRefs.valid(report.imageRefs(), report.commitSha()))) {
      throw invalid();
    }
    return new BuildReport(
        report.projectId(),
        report.source(),
        report.externalBuildId(),
        report.commitSha(),
        report.branch(),
        report.status(),
        hasImages ? report.imageRefs() : null,
        report.runUrl(),
        micros(report.startedAt()),
        micros(report.finishedAt()),
        report.errorSummary());
  }

  private static int rank(String status) {
    return terminal(status) ? 2 : ORDER.indexOf(status);
  }

  private static boolean terminal(String status) {
    return "succeeded".equals(status) || "failed".equals(status);
  }

  private MapSqlParameterSource params(BuildReport report) {
    return new MapSqlParameterSource()
        .addValue("project", report.projectId())
        .addValue("source", report.source())
        .addValue("external", report.externalBuildId())
        .addValue("commit", report.commitSha())
        .addValue("branch", report.branch())
        .addValue("status", report.status())
        .addValue("images", report.imageRefs() == null ? null : report.imageRefs().toString())
        .addValue("run", report.runUrl())
        .addValue("started", timestamp(report.startedAt()))
        .addValue("finished", timestamp(report.finishedAt()))
        .addValue("error", report.errorSummary());
  }

  private Stored stored(ResultSet rs) throws SQLException {
    return new Stored(
        rs.getString("id"),
        rs.getString("project_id"),
        rs.getString("commit_sha"),
        rs.getString("branch"),
        rs.getString("status"),
        json(rs.getString("image_refs")),
        rs.getString("run_url"),
        instant(rs.getTimestamp("started_at")),
        instant(rs.getTimestamp("finished_at")),
        rs.getString("error_summary"));
  }

  private JsonNode json(String value) {
    if (value == null) {
      return null;
    }
    try {
      return mapper.readTree(value);
    } catch (JsonProcessingException exception) {
      // 저장된 이미지가 깨져 있으면 어떤 보고와도 같지 않아서, 종료 상태 재수신은 충돌로 드러나요.
      return mapper.getNodeFactory().textNode("unreadable");
    }
  }

  private static Instant micros(Instant value) {
    return value == null ? null : value.truncatedTo(ChronoUnit.MICROS);
  }

  private static Timestamp timestamp(Instant value) {
    return value == null ? null : Timestamp.from(value);
  }

  private static Instant instant(Timestamp value) {
    return value == null ? null : value.toInstant();
  }

  private static boolean blank(String value) {
    return value == null || value.isBlank();
  }

  private static DaisyException invalid() {
    return new DaisyException(ErrorCode.VALIDATION_FAILED);
  }

  private static DaisyException conflict() {
    return new DaisyException(ErrorCode.STATE_CONFLICT);
  }
}
