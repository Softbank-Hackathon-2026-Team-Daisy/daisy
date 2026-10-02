package com.teamdaisy.server.jenkins.application;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyMap;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.contains;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.*;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.teamdaisy.server.common.error.DaisyException;
import com.teamdaisy.server.common.error.ErrorCode;
import com.teamdaisy.server.common.json.CanonicalJson;
import com.teamdaisy.server.jenkins.application.JenkinsCommandService.CommandScope;
import com.teamdaisy.server.jenkins.application.JenkinsCommandService.CommandTarget;
import java.util.List;
import java.util.Map;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.jdbc.core.namedparam.MapSqlParameterSource;
import org.springframework.jdbc.core.namedparam.NamedParameterJdbcTemplate;
import org.springframework.mock.env.MockEnvironment;

class JenkinsCommandServiceTest {
  private final NamedParameterJdbcTemplate jdbc = mock(NamedParameterJdbcTemplate.class);
  private JenkinsCommandService commands;

  @BeforeEach
  void setup() {
    var mapper = new ObjectMapper();
    commands =
        spy(
            new JenkinsCommandService(
                jdbc, mapper, new CanonicalJson(mapper), new MockEnvironment()));
  }

  @Test
  void conflictingResponseCannotOverwriteBoundRun() {
    when(jdbc.queryForList(anyString(), anyMap()))
        .thenReturn(List.of(Map.of("queue_id", 11L, "build_number", 7L)));
    assertThatThrownBy(() -> commands.dispatched("job_1", 12L, null, "queued"))
        .isInstanceOfSatisfying(
            DaisyException.class,
            e -> assertThat(e.errorCode()).isEqualTo(ErrorCode.STATE_CONFLICT));
    assertThatThrownBy(() -> commands.observed("job_1", 8L, "running"))
        .isInstanceOfSatisfying(
            DaisyException.class,
            e -> assertThat(e.errorCode()).isEqualTo(ErrorCode.STATE_CONFLICT));
    verify(jdbc, never()).update(anyString(), any(MapSqlParameterSource.class));
  }

  @Test
  void invalidRunStatusDoesNotTouchStorage() {
    assertThatThrownBy(() -> commands.dispatched("job_1", 11L, null, "applying"))
        .isInstanceOfSatisfying(
            DaisyException.class,
            e -> assertThat(e.errorCode()).isEqualTo(ErrorCode.VALIDATION_FAILED));
    verifyNoInteractions(jdbc);
  }

  @Test
  void invalidatedApprovalRejectsBeforeDispatchAttempt() {
    var pending =
        new CommandScope(
            "job_1",
            "dep_1",
            "prj_1",
            "request_1",
            "apply",
            null,
            "proposal-jenkins",
            "daisy/apply",
            "pending",
            "unknown",
            null,
            null,
            new ObjectMapper().createObjectNode());
    var rejected =
        new CommandScope(
            "job_1",
            "dep_1",
            "prj_1",
            "request_1",
            "apply",
            null,
            "proposal-jenkins",
            "daisy/apply",
            "rejected",
            "unknown",
            null,
            null,
            pending.payload());
    doReturn(pending, rejected).when(commands).lookup("job_1");
    doReturn(List.of(new CommandTarget("dt_1", "input", "plan_1", "digest", "state")))
        .when(commands)
        .executionTargets("job_1");
    when(jdbc.queryForList(anyString(), anyMap())).thenReturn(List.of(Map.of("id", "job_1")));
    when(jdbc.queryForObject(anyString(), any(MapSqlParameterSource.class), eq(Long.class)))
        .thenReturn(0L);
    assertThat(commands.claimPending().dispatchStatus()).isEqualTo("rejected");
    verify(jdbc).update(contains("approval_invalid_before_dispatch"), eq(Map.of("id", "job_1")));
    verify(jdbc, never()).update(contains("dispatch_attempts=dispatch_attempts+1"), anyMap());
  }
}
