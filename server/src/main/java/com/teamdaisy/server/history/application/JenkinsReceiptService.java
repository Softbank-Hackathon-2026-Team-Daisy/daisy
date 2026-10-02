package com.teamdaisy.server.history.application;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ObjectNode;
import com.teamdaisy.server.common.error.DaisyException;
import com.teamdaisy.server.common.error.ErrorCode;
import com.teamdaisy.server.jenkins.application.JenkinsCallbackService.Log;
import com.teamdaisy.server.jenkins.application.JenkinsCallbackService.Stage;
import com.teamdaisy.server.jenkins.application.JenkinsCommandService.CommandScope;
import java.sql.Timestamp;
import java.time.Duration;
import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.List;
import java.util.Map;
import java.util.Set;
import org.springframework.jdbc.core.namedparam.NamedParameterJdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;

/** Only sanitized structured text is accepted; never fetches remote console or artifact URLs. */
@Service
@Transactional(readOnly = true)
public class JenkinsReceiptService {
  private final NamedParameterJdbcTemplate jdbc;
  private final EventJournal journal;
  private final ObjectMapper mapper;

  public JenkinsReceiptService(
      NamedParameterJdbcTemplate jdbc, EventJournal journal, ObjectMapper mapper) {
    this.jdbc = jdbc;
    this.journal = journal;
    this.mapper = mapper;
  }

  @Transactional(propagation = Propagation.MANDATORY)
  public EventJournal.AppendResult log(
      CommandScope scope,
      String source,
      String eventId,
      long sequence,
      String target,
      Log log,
      String hash,
      Instant at) {
    require(
        log != null && log.message() != null && !log.message().isBlank(),
        ErrorCode.VALIDATION_FAILED);
    require(
        log.streamId() == null
            ? log.offset() == null && log.endOffset() == null
            : !log.streamId().isBlank()
                && log.streamId().length() <= 255
                && log.offset() != null
                && log.endOffset() != null
                && log.offset() >= 0
                && log.endOffset() > log.offset(),
        ErrorCode.VALIDATION_FAILED);
    ObjectNode payload = payload(scope, target, hash);
    var event =
        new DeploymentEvent(
            source,
            eventId,
            sequence,
            scope.id(),
            target,
            "log.batch",
            null,
            log.step(),
            log.level(),
            log.message(),
            payload,
            "applied",
            log.streamId() == null ? null : source + ":" + log.streamId(),
            log.offset(),
            log.endOffset(),
            at);
    return journal.appendDeployment(scope.projectId(), scope.deploymentId(), event, false);
  }

  @Transactional(propagation = Propagation.MANDATORY)
  public EventJournal.AppendResult stage(
      CommandScope scope,
      String source,
      String eventId,
      long sequence,
      String target,
      Stage stage,
      String hash,
      Instant at) {
    at = at.truncatedTo(ChronoUnit.MICROS);
    require(
        stage != null
            && stage.stageOccurrenceId() != null
            && !stage.stageOccurrenceId().isBlank()
            && stage.stageOccurrenceId().length() <= 255
            && stage.phase() != null
            && Set.of("started", "completed", "failed").contains(stage.phase())
            && stage.step() != null,
        ErrorCode.VALIDATION_FAILED);
    String type = "step." + stage.phase();
    ObjectNode payload =
        payload(scope, target, hash).put("stage_occurrence_id", stage.stageOccurrenceId());
    if (stage.step() != null) payload.put("step", stage.step());
    var event =
        new DeploymentEvent(
            source,
            eventId,
            sequence,
            scope.id(),
            target,
            type,
            stage.stageOccurrenceId(),
            stage.step(),
            stage.level(),
            stage.message(),
            payload,
            "applied",
            null,
            null,
            null,
            at);
    journal.validate(event);
    // Compare the original receipt before deriving duration: late starts must not change replay
    // identity.
    var old =
        jdbc.queryForList(
            "select id,seq,payload->>'receipt_hash' as receipt_hash from deployment_log where source=:source and source_event_id=:event",
            Map.of("source", source, "event", eventId));
    if (!old.isEmpty()) {
      var row = old.getFirst();
      require(hash.equals(row.get("receipt_hash")), ErrorCode.STATE_CONFLICT);
      return new EventJournal.AppendResult(
          ((Number) row.get("id")).longValue(), ((Number) row.get("seq")).longValue(), true);
    }
    var phases =
        jdbc.queryForList(
            """
        select event_type,step,occurred_at,source_sequence,processing_result from deployment_log
        where source=:source and execution_id=:execution and deployment_target_id=:target and stage_occurrence_id=:stage
        order by seq
        """,
            Map.of(
                "source",
                source,
                "execution",
                scope.id(),
                "target",
                target,
                "stage",
                stage.stageOccurrenceId()));
    for (var phase : phases) {
      require(
          stage.step() != null && stage.step().equals(phase.get("step")), ErrorCode.STATE_CONFLICT);
      require(!type.equals(phase.get("event_type")), ErrorCode.STATE_CONFLICT);
      if (!stage.phase().equals("started"))
        require("step.started".equals(phase.get("event_type")), ErrorCode.STATE_CONFLICT);
    }
    boolean hasAppliedStart =
        phases.stream()
            .anyMatch(
                p ->
                    p.get("event_type").equals("step.started")
                        && p.get("processing_result").equals("applied"));
    boolean stale =
        !current(scope, target, sequence, !stage.phase().equals("started") && hasAppliedStart)
            || phases.stream()
                .anyMatch(
                    p ->
                        stage.phase().equals("started")
                                && !p.get("event_type").equals("step.started")
                            || p.get("source_sequence") != null
                                && sequence <= ((Number) p.get("source_sequence")).longValue());
    if (!stage.phase().equals("started")) {
      var starts =
          phases.stream()
              .filter(
                  p ->
                      p.get("event_type").equals("step.started")
                          && p.get("processing_result").equals("applied"))
              .toList();
      if (!starts.isEmpty()) {
        Instant start = ((Timestamp) starts.getFirst().get("occurred_at")).toInstant();
        require(!at.isBefore(start), ErrorCode.VALIDATION_FAILED);
        payload
            .put("started_at", start.toString())
            .put("duration_ms", Duration.between(start, at).toMillis());
      }
    } else {
      for (var phase : phases)
        require(
            !at.isAfter(((Timestamp) phase.get("occurred_at")).toInstant()),
            ErrorCode.VALIDATION_FAILED);
    }
    event =
        new DeploymentEvent(
            source,
            eventId,
            sequence,
            scope.id(),
            target,
            type,
            stage.stageOccurrenceId(),
            stage.step(),
            stage.level(),
            stage.message(),
            payload,
            stale ? "ignored_stale" : "applied",
            null,
            null,
            null,
            at);
    return journal.appendDeployment(scope.projectId(), scope.deploymentId(), event, false);
  }

  private ObjectNode payload(CommandScope scope, String target, String hash) {
    return mapper
        .createObjectNode()
        .put("deployment_id", scope.deploymentId())
        .put("deployment_target_id", target)
        .put("execution_id", scope.id())
        .put("receipt_hash", hash);
  }

  private boolean current(
      CommandScope scope, String target, long sequence, boolean completingStartedStage) {
    List<Map<String, Object>> rows =
        jdbc.queryForList(
            "select current_execution_id,status,last_source_sequence from deployment_target where id=:id and deployment_id=:deployment",
            Map.of("id", target, "deployment", scope.deploymentId()));
    require(rows.size() == 1, ErrorCode.STATE_CONFLICT);
    var row = rows.getFirst();
    if (!scope.id().equals(row.get("current_execution_id"))) return false;
    boolean terminal =
        "succeeded".equals(row.get("status"))
            || "failed".equals(row.get("status"))
            || "cancelled".equals(row.get("status"));
    Object last = row.get("last_source_sequence");
    return completingStartedStage
        || !terminal && (last == null || sequence > ((Number) last).longValue());
  }

  private static void require(boolean value, ErrorCode code) {
    if (!value) throw new DaisyException(code);
  }
}
