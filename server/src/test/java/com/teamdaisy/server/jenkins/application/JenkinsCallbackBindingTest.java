package com.teamdaisy.server.jenkins.application;

import static org.assertj.core.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.teamdaisy.server.common.error.DaisyException;
import com.teamdaisy.server.common.json.CanonicalJson;
import com.teamdaisy.server.jenkins.application.JenkinsCommandService.CommandScope;
import java.time.Instant;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.jdbc.core.namedparam.MapSqlParameterSource;
import org.springframework.jdbc.core.namedparam.NamedParameterJdbcTemplate;
import org.springframework.mock.env.MockEnvironment;

class JenkinsCallbackBindingTest {
  @Test
  void targetStatesUseCommandRunVocabularyAndRequireMatchingTerminalFlag() {
    var jdbc = mock(NamedParameterJdbcTemplate.class);
    var mapper = new ObjectMapper();
    var commands =
        spy(
            new JenkinsCommandService(
                jdbc, mapper, new CanonicalJson(mapper), new MockEnvironment()));
    var command = scope(mapper, "accepted", "running", 1L, 1L, "prepare");
    doReturn(command).when(commands).lookup("job_1");
    doReturn(command).when(commands).requireScope("job_1", "dep_1", "dt_1");
    when(jdbc.update(anyString(), any(MapSqlParameterSource.class))).thenReturn(1);
    commands.recordTargetState("job_1", "dt_1", "generating", 1, Instant.EPOCH, false);
    var params = ArgumentCaptor.forClass(MapSqlParameterSource.class);
    verify(jdbc).update(contains("last_source_sequence<:sequence"), params.capture());
    assertThat(params.getValue().getValue("status")).isEqualTo("running");
    assertThatThrownBy(
            () -> commands.recordTargetState("job_1", "dt_1", "succeeded", 2, Instant.EPOCH, false))
        .isInstanceOf(DaisyException.class);
    verify(jdbc, times(1)).update(anyString(), any(MapSqlParameterSource.class));
  }

  @Test
  void earlyBindingAndSameTerminalReplayAreAllowedButConflictsAndWrongScopeFail() {
    var jdbc = mock(NamedParameterJdbcTemplate.class);
    var mapper = new ObjectMapper();
    var commands =
        spy(
            new JenkinsCommandService(
                jdbc, mapper, new CanonicalJson(mapper), new MockEnvironment()));
    var unbound = new HashMap<String, Object>();
    unbound.put("id", "job_1");
    unbound.put("queue_id", null);
    unbound.put("build_number", null);
    when(jdbc.queryForList(anyString(), anyMap())).thenReturn(List.of(unbound));
    CommandScope dispatching = scope(mapper, "dispatching", "unknown", null, null, "prepare");
    doReturn(dispatching).when(commands).lookup("job_1");
    doReturn(dispatching).when(commands).requireScope("job_1", "dep_1", "dt_1");
    commands.bindCallback("job_1", "req", "ci", "daisy/prepare", 11L, 7, "dt_1");
    verify(jdbc)
        .update(
            contains("build_number=coalesce(build_number,:build)"),
            any(MapSqlParameterSource.class));
    var order = inOrder(jdbc);
    order.verify(jdbc).queryForList(contains("from project "), anyMap());
    order.verify(jdbc).queryForList(contains("from deployment "), anyMap());
    order.verify(jdbc).queryForList(contains("order by id for update"), anyMap());
    order
        .verify(jdbc)
        .queryForList(
            contains("select id from jenkins_execution where id=:id for update"), anyMap());
    when(jdbc.queryForList(anyString(), anyMap()))
        .thenReturn(List.of(Map.of("id", "job_1", "queue_id", 11L, "build_number", 7L)));
    CommandScope terminal = scope(mapper, "accepted", "succeeded", 11L, 7L, "prepare");
    doReturn(terminal).when(commands).lookup("job_1");
    doReturn(terminal).when(commands).requireScope("job_1", "dep_1", "dt_1");
    commands.bindCallback("job_1", "req", "ci", "daisy/prepare", 11L, 7, "dt_1");
    assertThatThrownBy(
            () -> commands.bindCallback("job_1", "req", "ci", "daisy/prepare", 11L, 8, "dt_1"))
        .isInstanceOf(DaisyException.class);
    assertThatThrownBy(
            () -> commands.bindCallback("job_1", "wrong", "ci", "daisy/prepare", 11L, 7, "dt_1"))
        .isInstanceOf(DaisyException.class);
    assertThatThrownBy(
            () -> commands.bindCallback("job_1", "req", "other", "daisy/prepare", 11L, 7, "dt_1"))
        .isInstanceOf(DaisyException.class);
    doReturn(scope(mapper, "pending", "unknown", null, null, "prepare"))
        .when(commands)
        .requireScope("job_1", "dep_1", "dt_1");
    assertThatThrownBy(
            () -> commands.bindCallback("job_1", "req", "ci", "daisy/prepare", null, 7, "dt_1"))
        .isInstanceOf(DaisyException.class);
    doReturn(scope(mapper, "accepted", "running", 11L, 7L, "stop"))
        .when(commands)
        .requireScope("job_1", "dep_1", "dt_1");
    assertThatThrownBy(
            () -> commands.bindCallback("job_1", "req", "ci", "daisy/prepare", 11L, 7, "dt_1"))
        .isInstanceOf(DaisyException.class);
  }

  private CommandScope scope(
      ObjectMapper mapper, String dispatch, String run, Long queue, Long build, String operation) {
    return new CommandScope(
        "job_1",
        "dep_1",
        "prj_1",
        "req",
        operation,
        null,
        "ci",
        "daisy/prepare",
        dispatch,
        run,
        queue,
        build,
        mapper.createObjectNode());
  }
}
