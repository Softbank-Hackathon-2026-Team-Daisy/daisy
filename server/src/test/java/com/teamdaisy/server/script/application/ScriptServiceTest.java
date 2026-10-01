package com.teamdaisy.server.script.application;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.teamdaisy.server.common.error.DaisyException;
import com.teamdaisy.server.common.error.ErrorCode;
import com.teamdaisy.server.common.json.CanonicalJson;
import com.teamdaisy.server.jenkins.application.JenkinsCommandService;
import java.sql.Timestamp;
import java.time.Instant;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import org.junit.jupiter.api.Test;
import org.springframework.jdbc.core.namedparam.MapSqlParameterSource;
import org.springframework.jdbc.core.namedparam.NamedParameterJdbcTemplate;

class ScriptServiceTest {
  private final ObjectMapper mapper = new ObjectMapper().findAndRegisterModules();
  private final NamedParameterJdbcTemplate jdbc = mock(NamedParameterJdbcTemplate.class);
  private final JenkinsCommandService commands = mock(JenkinsCommandService.class);
  private final ScriptService service =
      new ScriptService(jdbc, mapper, new CanonicalJson(mapper), commands);
  private final Instant now = Instant.parse("2026-10-01T00:00:00Z");

  private ScriptService.ScriptInput input(String reference) {
    return new ScriptService.ScriptInput(
        "jenkins:instance:job:1",
        "code_1",
        reference,
        "sha256:" + "a".repeat(64),
        null,
        null,
        now,
        null);
  }

  private Map<String, Object> row() {
    var row = new HashMap<String, Object>();
    row.put("id", "scr_1");
    row.put("project_id", "prj_1");
    row.put("target_id", "tgt_1");
    row.put("source", "jenkins:instance:job:1");
    row.put("external_script_id", "code_1");
    row.put("artifact_ref", "artifact:code_1");
    row.put("content_digest", "sha256:" + "a".repeat(64));
    row.put("source_deployment_target_id", "dt_1");
    row.put("validated_at", Timestamp.from(now));
    return row;
  }

  private void scope() {
    when(commands.requireScope("exe_1", "dep_1", "dt_1"))
        .thenReturn(
            new JenkinsCommandService.CommandScope(
                "exe_1",
                "dep_1",
                "prj_1",
                "req_1",
                "prepare",
                null,
                "instance",
                "job",
                "submitted",
                "succeeded",
                null,
                1L,
                mapper.createObjectNode()));
  }

  @Test
  void immutableDuplicatesDoNotWriteAndDifferentReferencesConflict() {
    scope();
    when(jdbc.queryForList(anyString(), anyMap()))
        .thenAnswer(
            call -> {
              String sql = call.getArgument(0);
              if (sql.contains("from script")) return List.of(row());
              if (sql.contains("from deployment_target"))
                return List.of(Map.of("project_id", "prj_1", "target_id", "tgt_1"));
              return List.of(Map.of("id", "prj_1"));
            });
    assertEquals("scr_1", service.receive("exe_1", "dep_1", "dt_1", input("artifact:code_1")).id());
    var precise =
        new ScriptService.ScriptInput(
            "jenkins:instance:job:1",
            "code_1",
            "artifact:code_1",
            "sha256:" + "a".repeat(64),
            null,
            null,
            now.plusNanos(123),
            null);
    assertEquals("scr_1", service.receive("exe_1", "dep_1", "dt_1", precise).id());
    var error =
        assertThrows(
            DaisyException.class,
            () -> service.receive("exe_1", "dep_1", "dt_1", input("artifact:changed")));
    assertEquals(ErrorCode.STATE_CONFLICT, error.errorCode());
    verify(jdbc, never()).update(anyString(), any(MapSqlParameterSource.class));
  }

  @Test
  void stopCommandCannotReportNewScripts() {
    when(commands.requireScope("exe_1", "dep_1", "dt_1"))
        .thenReturn(
            new JenkinsCommandService.CommandScope(
                "exe_1",
                "dep_1",
                "prj_1",
                "req_1",
                "stop",
                null,
                "instance",
                "job",
                "submitted",
                "succeeded",
                null,
                1L,
                mapper.createObjectNode()));
    assertThrows(
        DaisyException.class,
        () -> service.receive("exe_1", "dep_1", "dt_1", input("artifact:code_1")));
    verifyNoInteractions(jdbc);
  }

  @Test
  void rejectsSignedReferencesAndRawMetadataAndExpiredArtifacts() {
    for (String reference :
        List.of(
            "https://host/code?signature=abc",
            "https://user:pass@host/code",
            "artifact:code#token"))
      assertThrows(DaisyException.class, () -> service.validate(input(reference)));
    var unsafe =
        new ScriptService.ScriptInput(
            "source",
            "id",
            "artifact:code",
            "sha256:" + "a".repeat(64),
            null,
            mapper.createObjectNode().put("tfstate", "raw"),
            now,
            null);
    assertThrows(DaisyException.class, () -> service.validate(unsafe));
    var expired = row();
    expired.put("artifact_expires_at", Timestamp.from(now));
    when(jdbc.queryForList(contains("from script where id="), anyMap()))
        .thenReturn(List.of(expired));
    assertThrows(DaisyException.class, () -> service.requireScript("scr_1", "prj_1", "tgt_1", now));
    var unavailable = row();
    unavailable.put("unavailable_at", Timestamp.from(now));
    when(jdbc.queryForList(contains("from script where id="), anyMap()))
        .thenReturn(List.of(unavailable));
    assertThrows(DaisyException.class, () -> service.requireScript("scr_1", "prj_1", "tgt_1", now));
  }
}
