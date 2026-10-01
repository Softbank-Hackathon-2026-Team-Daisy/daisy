package com.teamdaisy.server.script.application;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.teamdaisy.server.common.error.DaisyException;
import com.teamdaisy.server.common.error.ErrorCode;
import com.teamdaisy.server.common.json.CanonicalJson;
import com.teamdaisy.server.jenkins.application.JenkinsCommandService;
import java.nio.charset.StandardCharsets;
import java.sql.Timestamp;
import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.Map;
import java.util.Objects;
import java.util.Set;
import java.util.UUID;
import java.util.regex.Pattern;
import org.springframework.jdbc.core.namedparam.MapSqlParameterSource;
import org.springframework.jdbc.core.namedparam.NamedParameterJdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
@Transactional(readOnly = true)
public class ScriptService {
  private static final Pattern SECRET =
      Pattern.compile(
          "(?i)(-----BEGIN|bearer\\s+\\S+|(?:password|secret|token|credential|authorization|access[_-]?key)\\s*[:=]|AKIA[A-Z0-9]{16}|gh[pousr]_[A-Za-z0-9]{20,})");
  private static final Set<String> METADATA_FIELDS =
      Set.of("provider", "model", "tool_version", "validation_tool", "schema_version");
  private final NamedParameterJdbcTemplate jdbc;
  private final ObjectMapper mapper;
  private final CanonicalJson json;
  private final JenkinsCommandService commands;

  public ScriptService(
      NamedParameterJdbcTemplate jdbc,
      ObjectMapper mapper,
      CanonicalJson json,
      JenkinsCommandService commands) {
    this.jdbc = jdbc;
    this.mapper = mapper;
    this.json = json;
    this.commands = commands;
  }

  public record ScriptInput(
      String source,
      String externalScriptId,
      String artifactRef,
      String contentDigest,
      String compatibilityKey,
      JsonNode metadata,
      Instant validatedAt,
      Instant artifactExpiresAt) {}

  public record ScriptInfo(
      String id,
      String projectId,
      String targetId,
      String artifactRef,
      String contentDigest,
      String sourceDeploymentTargetId,
      Instant artifactExpiresAt,
      Instant unavailableAt) {}

  /** Called only after adapter authentication; source namespaces must come from that adapter. */
  @Transactional
  public ScriptInfo receive(
      String executionId, String deploymentId, String deploymentTargetId, ScriptInput input) {
    input = normalized(input);
    validate(input);
    text(executionId, 64);
    text(deploymentId, 64);
    text(deploymentTargetId, 64);
    var scope = commands.requireScope(executionId, deploymentId, deploymentTargetId);
    require(Set.of("prepare", "replan").contains(scope.operation()), ErrorCode.STATE_CONFLICT);
    lock("project", scope.projectId());
    lock("deployment", deploymentId);
    var targets =
        jdbc.queryForList(
            "select project_id,target_id from deployment_target where id=:id and deployment_id=:deployment for update",
            Map.of("id", deploymentTargetId, "deployment", deploymentId));
    require(
        targets.size() == 1 && scope.projectId().equals(targets.getFirst().get("project_id")),
        ErrorCode.STATE_CONFLICT);
    String target = (String) targets.getFirst().get("target_id");
    jdbc.queryForList(
        "select pg_advisory_xact_lock(hashtextextended(:identity,0))",
        Map.of("identity", "script:" + input.source() + ":" + input.externalScriptId()));
    var existing =
        jdbc.queryForList(
            "select * from script where source=:source and external_script_id=:external",
            Map.of("source", input.source(), "external", input.externalScriptId()));
    if (!existing.isEmpty()) {
      var row = existing.getFirst();
      ScriptInput original =
          new ScriptInput(
              (String) row.get("source"),
              (String) row.get("external_script_id"),
              (String) row.get("artifact_ref"),
              (String) row.get("content_digest"),
              (String) row.get("compatibility_key"),
              parse(row.get("metadata")),
              instant(row.get("validated_at")),
              instant(row.get("artifact_expires_at")));
      require(
          scope.projectId().equals(row.get("project_id"))
              && target.equals(row.get("target_id"))
              && json.hash(mapper.valueToTree(input))
                  .equals(json.hash(mapper.valueToTree(original))),
          ErrorCode.STATE_CONFLICT);
      return info(row);
    }
    int version =
        Objects.requireNonNull(
            jdbc.queryForObject(
                "select coalesce(max(version),0)+1 from script where project_id=:project and target_id=:target",
                Map.of("project", scope.projectId(), "target", target),
                Integer.class));
    String id = "scr_" + UUID.randomUUID().toString().replace("-", "");
    var p =
        new MapSqlParameterSource()
            .addValue("id", id)
            .addValue("project", scope.projectId())
            .addValue("target", target)
            .addValue("version", version)
            .addValue("source", input.source())
            .addValue("external", input.externalScriptId())
            .addValue("deploymentTarget", deploymentTargetId)
            .addValue("ref", input.artifactRef())
            .addValue("digest", input.contentDigest())
            .addValue("compatibility", input.compatibilityKey())
            .addValue(
                "metadata", input.metadata() == null ? null : json.canonicalize(input.metadata()))
            .addValue("validated", Timestamp.from(input.validatedAt()))
            .addValue("expires", timestamp(input.artifactExpiresAt()));
    jdbc.update(
        """
        insert into script(id,project_id,target_id,version,source,external_script_id,source_deployment_target_id,
          artifact_ref,content_digest,compatibility_key,metadata,validated_at,received_at,artifact_expires_at,unavailable_at)
        values(:id,:project,:target,:version,:source,:external,:deploymentTarget,:ref,:digest,:compatibility,
          cast(:metadata as jsonb),:validated,now(),:expires,null)
        """,
        p);
    return new ScriptInfo(
        id,
        scope.projectId(),
        target,
        input.artifactRef(),
        input.contentDigest(),
        deploymentTargetId,
        input.artifactExpiresAt(),
        null);
  }

  public ScriptInfo requireScript(String id, String projectId, String targetId, Instant now) {
    text(id, 64);
    text(projectId, 64);
    text(targetId, 64);
    require(now != null, ErrorCode.VALIDATION_FAILED);
    var records =
        jdbc.queryForList(
            "select * from script where id=:id and project_id=:project and target_id=:target",
            Map.of("id", id, "project", projectId, "target", targetId));
    require(records.size() == 1, ErrorCode.STATE_CONFLICT);
    ScriptInfo result = info(records.getFirst());
    require(
        result.unavailableAt() == null
            && (result.artifactExpiresAt() == null || result.artifactExpiresAt().isAfter(now)),
        ErrorCode.STATE_CONFLICT);
    return result;
  }

  void validate(ScriptInput input) {
    require(input != null, ErrorCode.VALIDATION_FAILED);
    text(input.source(), 512);
    text(input.externalScriptId(), 255);
    text(input.artifactRef(), 4096);
    require(
        input
            .artifactRef()
            .chars()
            .noneMatch(c -> c < 33 || c == 127 || c == '?' || c == '#' || c == '@'),
        ErrorCode.VALIDATION_FAILED);
    require(
        input.contentDigest() != null && input.contentDigest().matches("sha256:[0-9a-f]{64}"),
        ErrorCode.VALIDATION_FAILED);
    if (input.compatibilityKey() != null) text(input.compatibilityKey(), 255);
    require(
        input.validatedAt() != null
            && (input.artifactExpiresAt() == null
                || input.artifactExpiresAt().isAfter(input.validatedAt())),
        ErrorCode.VALIDATION_FAILED);
    if (input.metadata() != null) {
      require(input.metadata().isObject(), ErrorCode.VALIDATION_FAILED);
      input
          .metadata()
          .fields()
          .forEachRemaining(
              field -> {
                require(
                    METADATA_FIELDS.contains(field.getKey())
                        && (field.getValue().isTextual() || field.getValue().isIntegralNumber()),
                    ErrorCode.VALIDATION_FAILED);
                if (field.getValue().isTextual()) text(field.getValue().textValue(), 1024);
              });
    }
    json.copy(mapper.valueToTree(input));
  }

  // PostgreSQL stores microseconds: use that same precision for immutable receipt comparisons.
  static ScriptInput normalized(ScriptInput input) {
    if (input == null) return null;
    return new ScriptInput(
        input.source(),
        input.externalScriptId(),
        input.artifactRef(),
        input.contentDigest(),
        input.compatibilityKey(),
        input.metadata(),
        input.validatedAt() == null ? null : input.validatedAt().truncatedTo(ChronoUnit.MICROS),
        input.artifactExpiresAt() == null
            ? null
            : input.artifactExpiresAt().truncatedTo(ChronoUnit.MICROS));
  }

  private ScriptInfo info(Map<String, Object> row) {
    return new ScriptInfo(
        (String) row.get("id"),
        (String) row.get("project_id"),
        (String) row.get("target_id"),
        (String) row.get("artifact_ref"),
        (String) row.get("content_digest"),
        (String) row.get("source_deployment_target_id"),
        instant(row.get("artifact_expires_at")),
        instant(row.get("unavailable_at")));
  }

  private JsonNode parse(Object body) {
    if (body == null) return null;
    try {
      return mapper.readTree(body.toString());
    } catch (Exception error) {
      throw new DaisyException(ErrorCode.INTERNAL);
    }
  }

  private static Instant instant(Object value) {
    return value == null ? null : ((Timestamp) value).toInstant();
  }

  private static Timestamp timestamp(Instant value) {
    return value == null ? null : Timestamp.from(value);
  }

  private void lock(String table, String id) {
    require(
        !jdbc.queryForList("select id from " + table + " where id=:id for update", Map.of("id", id))
            .isEmpty(),
        ErrorCode.NOT_FOUND);
  }

  private static void text(String value, int max) {
    require(
        value != null
            && !value.isBlank()
            && value.getBytes(StandardCharsets.UTF_8).length <= max
            && !SECRET.matcher(value).find(),
        ErrorCode.VALIDATION_FAILED);
  }

  private static void require(boolean ok, ErrorCode error) {
    if (!ok) throw new DaisyException(error);
  }
}
