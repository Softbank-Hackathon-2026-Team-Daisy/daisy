package com.teamdaisy.server.ai.application;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.teamdaisy.server.common.error.DaisyException;
import com.teamdaisy.server.common.error.ErrorCode;
import com.teamdaisy.server.common.json.CanonicalJson;
import com.teamdaisy.server.jenkins.application.JenkinsCommandService;
import java.math.BigDecimal;
import java.nio.charset.StandardCharsets;
import java.sql.Timestamp;
import java.time.Instant;
import java.util.Map;
import java.util.Set;
import java.util.UUID;
import java.util.regex.Pattern;
import org.springframework.jdbc.core.namedparam.MapSqlParameterSource;
import org.springframework.jdbc.core.namedparam.NamedParameterJdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
@Transactional(readOnly = true)
public class AiUsageService {
  private static final Set<String> DETAIL_FIELDS =
      Set.of(
          "cached_input_tokens",
          "cache_read_input_tokens",
          "cache_creation_input_tokens",
          "reasoning_tokens",
          "total_tokens");
  private static final Pattern SECRET =
      Pattern.compile(
          "(?i)(bearer\\s+\\S+|(?:password|secret|token|credential|authorization|access[_-]?key)\\s*[:=]|AKIA[A-Z0-9]{16}|gh[pousr]_[A-Za-z0-9]{20,})");
  private final NamedParameterJdbcTemplate jdbc;
  private final ObjectMapper mapper;
  private final CanonicalJson json;
  private final JenkinsCommandService commands;

  public AiUsageService(
      NamedParameterJdbcTemplate jdbc,
      ObjectMapper mapper,
      CanonicalJson json,
      JenkinsCommandService commands) {
    this.jdbc = jdbc;
    this.mapper = mapper;
    this.json = json;
    this.commands = commands;
  }

  public record UsageInput(
      String source,
      String externalCallId,
      String provider,
      String model,
      String step,
      int attempt,
      String status,
      Long inputTokens,
      Long outputTokens,
      JsonNode usageDetails,
      BigDecimal costUsd,
      String costBasis,
      Instant occurredAt) {}

  public record Receipt(String id, boolean duplicate) {}

  public boolean hasUsage(String deploymentTargetId) {
    text(deploymentTargetId, 64);
    return java.util.Objects.requireNonNull(
            jdbc.queryForObject(
                "select count(*) from ai_usage where deployment_target_id=:target",
                Map.of("target", deploymentTargetId),
                Long.class))
        > 0;
  }

  /**
   * Proposed v1 prepare/replan protocol uses generate/fix; unknown usage stays NULL, including late
   * receipts.
   */
  @Transactional
  public Receipt receive(
      String executionId, String deploymentId, String deploymentTargetId, UsageInput input) {
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
            "select project_id,ai_reused from deployment_target where id=:id and deployment_id=:deployment for update",
            Map.of("id", deploymentTargetId, "deployment", deploymentId));
    require(
        targets.size() == 1 && scope.projectId().equals(targets.getFirst().get("project_id")),
        ErrorCode.STATE_CONFLICT);
    require(!Boolean.TRUE.equals(targets.getFirst().get("ai_reused")), ErrorCode.STATE_CONFLICT);
    jdbc.queryForList(
        "select pg_advisory_xact_lock(hashtextextended(:identity,0))",
        Map.of("identity", "usage:" + input.source() + ":" + input.externalCallId()));
    String hash =
        json.hash(
            mapper.valueToTree(
                Map.of(
                    "execution_id",
                    executionId,
                    "deployment_target_id",
                    deploymentTargetId,
                    "usage",
                    input)));
    var existing =
        jdbc.queryForList(
            "select id,payload_hash from ai_usage where source=:source and external_call_id=:external",
            Map.of("source", input.source(), "external", input.externalCallId()));
    if (!existing.isEmpty()) {
      require(hash.equals(existing.getFirst().get("payload_hash")), ErrorCode.STATE_CONFLICT);
      return new Receipt((String) existing.getFirst().get("id"), true);
    }
    String id = "aiu_" + UUID.randomUUID().toString().replace("-", "");
    var p =
        new MapSqlParameterSource()
            .addValue("id", id)
            .addValue("execution", executionId)
            .addValue("target", deploymentTargetId)
            .addValue("source", input.source())
            .addValue("external", input.externalCallId())
            .addValue("hash", hash)
            .addValue("provider", input.provider())
            .addValue("model", input.model())
            .addValue("step", input.step())
            .addValue("attempt", input.attempt())
            .addValue("status", input.status())
            .addValue("input", input.inputTokens())
            .addValue("output", input.outputTokens())
            .addValue(
                "details",
                input.usageDetails() == null ? null : json.canonicalize(input.usageDetails()))
            .addValue("cost", input.costUsd())
            .addValue("basis", input.costBasis())
            .addValue("at", Timestamp.from(input.occurredAt()));
    jdbc.update(
        """
        insert into ai_usage(id,execution_id,deployment_target_id,source,external_call_id,payload_hash,provider,
          model,step,attempt,status,input_tokens,output_tokens,usage_details,cost_usd,cost_basis,occurred_at,received_at)
        values(:id,:execution,:target,:source,:external,:hash,:provider,:model,:step,:attempt,:status,:input,:output,
          cast(:details as jsonb),:cost,:basis,:at,now())
        """,
        p);
    return new Receipt(id, false);
  }

  void validate(UsageInput input) {
    require(input != null, ErrorCode.VALIDATION_FAILED);
    text(input.source(), 512);
    text(input.externalCallId(), 255);
    text(input.provider(), 64);
    text(input.model(), 128);
    require(
        input.step() != null
            && Set.of("generate", "fix").contains(input.step())
            && input.attempt() >= 1
            && input.attempt() <= 3,
        ErrorCode.VALIDATION_FAILED);
    require(
        input.status() != null
            && Set.of("succeeded", "failed", "unknown").contains(input.status())
            && input.occurredAt() != null,
        ErrorCode.VALIDATION_FAILED);
    require(
        (input.inputTokens() == null || input.inputTokens() >= 0)
            && (input.outputTokens() == null || input.outputTokens() >= 0),
        ErrorCode.VALIDATION_FAILED);
    require(
        input.costUsd() == null
            ? input.costBasis() == null
            : input.costBasis() != null
                && Set.of("reported", "estimated").contains(input.costBasis())
                && input.costUsd().signum() >= 0
                && input.costUsd().scale() <= 10
                && input.costUsd().precision() - input.costUsd().scale() <= 10,
        ErrorCode.VALIDATION_FAILED);
    if (input.usageDetails() != null) {
      require(input.usageDetails().isObject(), ErrorCode.VALIDATION_FAILED);
      input
          .usageDetails()
          .fields()
          .forEachRemaining(
              field ->
                  require(
                      DETAIL_FIELDS.contains(field.getKey())
                          && field.getValue().isIntegralNumber()
                          && field.getValue().canConvertToLong()
                          && field.getValue().longValue() >= 0,
                      ErrorCode.VALIDATION_FAILED));
    }
    json.copy(mapper.valueToTree(input));
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
            && value.matches("[A-Za-z0-9_.:/ -]+")
            && !value.isBlank()
            && value.getBytes(StandardCharsets.UTF_8).length <= max
            && !SECRET.matcher(value).find(),
        ErrorCode.VALIDATION_FAILED);
  }

  private static void require(boolean ok, ErrorCode error) {
    if (!ok) throw new DaisyException(error);
  }
}
