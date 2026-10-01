package com.teamdaisy.server.jenkins.application;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyMap;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.*;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.teamdaisy.server.common.error.DaisyException;
import com.teamdaisy.server.common.json.CanonicalJson;
import com.teamdaisy.server.history.application.EventJournal;
import com.teamdaisy.server.jenkins.infrastructure.JenkinsClient.LogChunk;
import java.nio.charset.StandardCharsets;
import java.sql.Timestamp;
import java.time.Instant;
import java.util.Arrays;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.jdbc.core.namedparam.MapSqlParameterSource;
import org.springframework.jdbc.core.namedparam.NamedParameterJdbcTemplate;
import org.springframework.mock.env.MockEnvironment;

class JenkinsConsoleServiceTest {
  private final ObjectMapper mapper = new ObjectMapper();
  private final CanonicalJson json = new CanonicalJson(mapper);
  private final NamedParameterJdbcTemplate jdbc = mock(NamedParameterJdbcTemplate.class);
  private final EventJournal journal = mock(EventJournal.class);
  private final MockEnvironment env =
      new MockEnvironment()
          .withProperty("daisy.jenkins.console-enabled", "true")
          .withProperty("daisy.jenkins.console-sanitized-utf8-confirmed", "true");
  private final JenkinsConsoleService consoles =
      new JenkinsConsoleService(jdbc, journal, mapper, json, env);

  private LogChunk chunk(String text, boolean more) {
    byte[] bytes = text.getBytes(StandardCharsets.UTF_8);
    return new LogChunk(bytes, bytes.length, more);
  }

  private JenkinsConsoleService.Owner owner() {
    String stream =
        "jenkins-console:"
            + json.hash(
                mapper.valueToTree(
                    Map.of("instance", "proposal-jenkins", "job", "daisy/prepare", "build", 7L)));
    return new JenkinsConsoleService.Owner(
        "job_1",
        "dep_1",
        "prj_1",
        "proposal-jenkins",
        "daisy/prepare",
        7,
        0,
        false,
        Instant.EPOCH,
        stream);
  }

  private void storedCursor(long cursor) {
    Map<String, Object> row =
        new HashMap<>(
            Map.of(
                "id",
                "job_1",
                "deployment_id",
                "dep_1",
                "project_id",
                "prj_1",
                "instance_id",
                "proposal-jenkins",
                "job_full_name",
                "daisy/prepare",
                "build_number",
                7L,
                "log_owner_execution_id",
                "job_1",
                "log_cursor",
                cursor,
                "log_complete",
                false,
                "created_at",
                Timestamp.from(Instant.EPOCH)));
    when(jdbc.queryForList(anyString(), anyMap()))
        .thenAnswer(
            invocation ->
                invocation.<String>getArgument(0).startsWith("select e.*")
                    ? List.of(row)
                    : List.of(Map.of("id", "any")));
  }

  @Test
  void retainsSplitUtf8AndTrailingLineWithoutInventingCharacterOffsets() {
    byte[] prefix = "done\n가".getBytes(StandardCharsets.UTF_8);
    var parsed =
        JenkinsConsoleService.parse(
            100,
            new LogChunk(Arrays.copyOf(prefix, prefix.length - 1), 100 + prefix.length - 1, true));
    assertThat(parsed.consumed()).isEqualTo(5);
    assertThat(parsed.blocks().getFirst().text()).isEqualTo("done\n");
    assertThat(parsed.complete()).isFalse();
    assertThat(JenkinsConsoleService.parse(0, chunk("가나다", true)).consumed()).isZero();
    assertThat(JenkinsConsoleService.parse(0, chunk("가나다", false)).consumed()).isEqualTo(9);
  }

  @Test
  void invalidByteRangeUtf8AndOversizedLineAreRejected() {
    assertThatThrownBy(() -> JenkinsConsoleService.parse(0, new LogChunk(new byte[] {1}, 2, true)))
        .isInstanceOf(DaisyException.class);
    assertThatThrownBy(
            () -> JenkinsConsoleService.parse(0, new LogChunk(new byte[] {(byte) 0xe3}, 1, false)))
        .isInstanceOf(DaisyException.class);
    assertThatThrownBy(() -> JenkinsConsoleService.parse(0, chunk("x".repeat(16385), true)))
        .isInstanceOf(DaisyException.class);
  }

  @Test
  void groupsOnlyAtCompleteLineBoundariesWithinMessageLimit() {
    var parsed = JenkinsConsoleService.parse(0, chunk("가\n".repeat(5000), true));
    assertThat(parsed.blocks()).hasSize(2);
    assertThat(parsed.blocks())
        .allSatisfy(
            block -> {
              assertThat(block.bytes().length).isLessThanOrEqualTo(16384);
              assertThat(block.text()).endsWith("\n");
            });
    assertThat(parsed.consumed()).isEqualTo(20000);
  }

  @Test
  void duplicateCommittedCursorDiscardsChunkWithoutWritingEvents() {
    storedCursor(3);
    assertThat(consoles.commit(owner(), chunk("ok\n", true))).isFalse();
    verify(journal, never()).appendDeployment(anyString(), anyString(), any(), anyBoolean());
    verify(jdbc, never()).update(anyString(), any(MapSqlParameterSource.class));
  }

  @Test
  void eofCursorAndEventsAreWrittenInSameServiceTransaction() {
    storedCursor(0);
    assertThat(consoles.commit(owner(), chunk("가", false))).isTrue();
    var p = ArgumentCaptor.forClass(MapSqlParameterSource.class);
    verify(jdbc).update(contains("log_cursor=:cursor,log_complete=:complete"), p.capture());
    assertThat(p.getValue().getValue("cursor")).isEqualTo(3L);
    assertThat(p.getValue().getValue("complete")).isEqualTo(true);
    var order = inOrder(journal, jdbc);
    order.verify(journal).validate(any());
    order.verify(journal).appendDeployment(eq("prj_1"), eq("dep_1"), any(), eq(false));
    order.verify(jdbc).update(contains("log_cursor=:cursor"), any(MapSqlParameterSource.class));
  }

  @Test
  void emptyEofCompletesWithoutDataEventAndCursorAdvance() {
    storedCursor(0);
    assertThat(consoles.commit(owner(), chunk("", false))).isTrue();
    verify(journal, never()).appendDeployment(anyString(), anyString(), any(), anyBoolean());
    var p = ArgumentCaptor.forClass(MapSqlParameterSource.class);
    verify(jdbc).update(contains("log_complete=:complete"), p.capture());
    assertThat(p.getValue().getValue("cursor")).isEqualTo(0L);
    assertThat(p.getValue().getValue("complete")).isEqualTo(true);
  }

  @Test
  void secretMarkerSplitAcrossBlocksRejectsWholeBatchBeforeStorage() {
    EventJournal actual = new EventJournal(jdbc, mapper, json);
    var service = new JenkinsConsoleService(jdbc, actual, mapper, json, env);
    // First block reaches its limit, so value would otherwise be stored in another block.
    String log = "x".repeat(16376) + "\ntoken=\n" + "sensitive-value\n";
    assertThatThrownBy(() -> service.commit(owner(), chunk(log, false)))
        .isInstanceOf(DaisyException.class);
    verifyNoInteractions(jdbc);
  }
}
