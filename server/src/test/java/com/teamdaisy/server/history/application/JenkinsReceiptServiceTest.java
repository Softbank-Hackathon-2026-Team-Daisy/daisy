package com.teamdaisy.server.history.application;

import static org.assertj.core.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.teamdaisy.server.common.error.DaisyException;
import com.teamdaisy.server.jenkins.application.JenkinsCallbackService.Log;
import com.teamdaisy.server.jenkins.application.JenkinsCallbackService.Stage;
import com.teamdaisy.server.jenkins.application.JenkinsCommandService.CommandScope;
import java.sql.Timestamp;
import java.time.Instant;
import java.util.List;
import java.util.Map;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.jdbc.core.namedparam.NamedParameterJdbcTemplate;

class JenkinsReceiptServiceTest {
  private final NamedParameterJdbcTemplate jdbc = mock(NamedParameterJdbcTemplate.class);
  private final EventJournal journal = mock(EventJournal.class);
  private final ObjectMapper mapper = new ObjectMapper();
  private final JenkinsReceiptService receipts = new JenkinsReceiptService(jdbc, journal, mapper);
  private final CommandScope scope = new CommandScope("job", "dep", "prj", "req", "prepare", null,
      "ci", "job", "accepted", "running", null, 7L, mapper.createObjectNode());
  private final Instant at = Instant.parse("2026-10-01T00:00:03Z");

  @Test
  void deploymentWideLogsRemainVisibleWithoutTargetStateQuery() {
    receipts.log(scope, "source", "log1", 1L, null, new Log("info", null, "sanitized text", null, null, null), "hash", at);
    var event = ArgumentCaptor.forClass(DeploymentEvent.class);
    verify(journal).appendDeployment(eq("prj"), eq("dep"), event.capture(), eq(false));
    assertThat(event.getValue().processingResult()).isEqualTo("applied");
    assertThat(event.getValue().deploymentTargetId()).isNull();
    verifyNoInteractions(jdbc);
  }

  @Test
  void missingStartOmitsDurationAndDuplicateDoesNotRecalculateAfterLateStart() {
    when(jdbc.queryForList(anyString(), anyMap())).thenReturn(List.of());
    when(jdbc.queryForList(contains("select current_execution_id"), anyMap())).thenReturn(List.of(Map.of("current_execution_id", "job")));
    receipts.stage(scope, "source", "finish", 2L, "dt", new Stage("occ", "plan", "completed", "info", null), "hash", at);
    var event = ArgumentCaptor.forClass(DeploymentEvent.class);
    verify(journal).appendDeployment(eq("prj"), eq("dep"), event.capture(), eq(false));
    assertThat(event.getValue().payload().has("duration_ms")).isFalse();
    when(jdbc.queryForList(contains("payload->>'receipt_hash'"), anyMap()))
        .thenReturn(List.of(Map.of("id", 1L, "seq", 2L, "receipt_hash", "hash")));
    assertThat(receipts.stage(scope, "source", "finish", 2L, "dt", new Stage("occ", "plan", "completed", "info", null), "hash", at).duplicate()).isTrue();
    assertThatThrownBy(() -> receipts.stage(scope, "source", "finish", 2L, "dt", new Stage("occ", "plan", "completed", "info", null), "changed", at))
        .isInstanceOf(DaisyException.class);
    verify(journal, times(1)).appendDeployment(anyString(), anyString(), any(), eq(false));
  }

  @Test
  void matchingOccurrenceProducesDurationAndLateStartIsIgnored() {
    when(jdbc.queryForList(anyString(), anyMap())).thenReturn(List.of());
    when(jdbc.queryForList(contains("select current_execution_id"), anyMap())).thenReturn(List.of(Map.of("current_execution_id", "job")));
    when(jdbc.queryForList(contains("select event_type,step"), anyMap())).thenReturn(List.of(Map.of("event_type", "step.started",
        "step", "plan", "occurred_at", Timestamp.from(at.minusSeconds(2)), "source_sequence", 1L, "processing_result", "applied")));
    receipts.stage(scope, "source", "finish", 2L, "dt", new Stage("occ", "plan", "completed", "info", null), "hash", at);
    var event = ArgumentCaptor.forClass(DeploymentEvent.class);
    verify(journal).appendDeployment(eq("prj"), eq("dep"), event.capture(), eq(false));
    assertThat(event.getValue().payload().path("duration_ms").asLong()).isEqualTo(2000L);
    when(jdbc.queryForList(contains("select event_type,step"), anyMap())).thenReturn(List.of(Map.of("event_type", "step.completed",
        "step", "plan", "occurred_at", Timestamp.from(at), "source_sequence", 2L, "processing_result", "applied")));
    receipts.stage(scope, "source", "late-start", 1L, "dt", new Stage("occ", "plan", "started", "info", null), "start-hash", at.minusSeconds(2));
    verify(journal, times(2)).appendDeployment(eq("prj"), eq("dep"), event.capture(), eq(false));
    assertThat(event.getValue().processingResult()).isEqualTo("ignored_stale");
  }
}
