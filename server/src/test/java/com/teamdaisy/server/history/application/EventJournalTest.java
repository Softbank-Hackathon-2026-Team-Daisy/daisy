package com.teamdaisy.server.history.application;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.teamdaisy.server.common.error.DaisyException;
import com.teamdaisy.server.common.error.ErrorCode;
import com.teamdaisy.server.common.json.CanonicalJson;
import com.teamdaisy.server.deployment.application.ExecutionAccess;
import java.time.Instant;
import java.util.List;
import java.util.Map;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.jdbc.core.namedparam.MapSqlParameterSource;
import org.springframework.jdbc.core.namedparam.NamedParameterJdbcTemplate;

class EventJournalTest {
  private final ObjectMapper mapper = new ObjectMapper().findAndRegisterModules();
  private final NamedParameterJdbcTemplate jdbc = mock(NamedParameterJdbcTemplate.class);
  private final EventJournal journal = new EventJournal(jdbc, mapper, new CanonicalJson(mapper));

  private DeploymentEvent event(String result, String message) {
    return new DeploymentEvent(
        "jenkins:trusted:job:1",
        "evt-1",
        1L,
        null,
        null,
        "deployment.state_changed",
        null,
        null,
        "info",
        message,
        mapper.createObjectNode().put("status", "running"),
        result,
        null,
        null,
        null,
        Instant.parse("2026-10-01T00:00:00Z"));
  }

  @Test
  void sourceHashDoesNotDependOnStaleClassificationAndDuplicateConsumesNoSequence() {
    DeploymentEvent original = event("applied", null);
    String hash = journal.sourceHash("dep_1", original);
    assertEquals(hash, journal.sourceHash("dep_1", event("ignored_stale", null)));
    when(jdbc.queryForList(anyString(), anyMap()))
        .thenAnswer(
            call -> {
              String sql = call.getArgument(0);
              return sql.contains("project_id from deployment")
                  ? List.of(Map.of("project_id", "prj_1"))
                  : List.of(Map.of("id", "prj_1"));
            });
    when(jdbc.queryForList(
            contains("from deployment_log where source="), any(MapSqlParameterSource.class)))
        .thenReturn(List.of(Map.of("id", 7L, "seq", 3L, "payload_hash", hash)));
    assertEquals(
        new EventJournal.AppendResult(7, 3, true),
        journal.appendDeployment("prj_1", "dep_1", event("ignored_stale", null), true));
    verify(jdbc, never()).queryForObject(startsWith("update "), anyMap(), eq(Long.class));
    var error =
        assertThrows(
            DaisyException.class,
            () -> journal.appendDeployment("prj_1", "dep_1", event("applied", "different"), false));
    assertEquals(ErrorCode.STATE_CONFLICT, error.errorCode());
  }

  @Test
  void rejectsSecretsOversizeAndUnknownPayloadBeforeWrites() {
    assertThrows(DaisyException.class, () -> journal.validate(event("applied", "password=abc")));
    assertThrows(DaisyException.class, () -> journal.validate(event("applied", "a".repeat(16385))));
    var unsafe = event("applied", null);
    ((com.fasterxml.jackson.databind.node.ObjectNode) unsafe.payload()).put("tfstate", "raw");
    assertThrows(DaisyException.class, () -> journal.validate(unsafe));
    verifyNoInteractions(jdbc);
  }

  @Test
  void cursorIsBoundedUnsignedDecimal() {
    assertEquals(0, EventSseService.parseCursor(null));
    assertEquals(25, EventSseService.parseCursor("25"));
    for (String invalid : List.of("-1", "+1", "1.0", "9223372036854775808"))
      assertThrows(DaisyException.class, () -> EventSseService.parseCursor(invalid));
  }

  @Test
  void sseDeniesMissingSharedGuardBeforeReadingHistory() {
    @SuppressWarnings("unchecked")
    ObjectProvider<ExecutionAccess> absent = mock(ObjectProvider.class);
    EventSseService streams = new EventSseService(journal, absent, 2, 1);
    try {
      DaisyException error =
          assertThrows(DaisyException.class, () -> streams.openProject("acct_1", "prj_1", null));
      assertEquals(ErrorCode.FORBIDDEN, error.errorCode());
      verifyNoInteractions(jdbc);
    } finally {
      streams.shutdown();
    }
  }
}
