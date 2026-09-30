package com.teamdaisy.server.jenkins.application;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.teamdaisy.server.common.error.DaisyException;
import com.teamdaisy.server.common.error.ErrorCode;
import com.teamdaisy.server.common.json.CanonicalJson;
import com.teamdaisy.server.history.application.DeploymentEvent;
import com.teamdaisy.server.history.application.EventJournal;
import com.teamdaisy.server.jenkins.infrastructure.JenkinsClient.LogChunk;
import java.nio.ByteBuffer;
import java.nio.charset.CodingErrorAction;
import java.nio.charset.StandardCharsets;
import java.time.Instant;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Base64;
import java.util.List;
import java.util.Map;
import org.springframework.core.env.Environment;
import org.springframework.jdbc.core.namedparam.MapSqlParameterSource;
import org.springframework.jdbc.core.namedparam.NamedParameterJdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;

/** Only sanitized UTF-8 output with byte-exact progressive offsets can enter this collector. */
@Service
@Transactional(readOnly = true)
public class JenkinsConsoleService {
  static final int MESSAGE_BYTES = 16 * 1024;
  private final NamedParameterJdbcTemplate jdbc;
  private final EventJournal journal;
  private final ObjectMapper mapper;
  private final CanonicalJson json;
  private final Environment env;

  public JenkinsConsoleService(NamedParameterJdbcTemplate jdbc, EventJournal journal,
      ObjectMapper mapper, CanonicalJson json, Environment env) {
    this.jdbc = jdbc; this.journal = journal; this.mapper = mapper; this.json = json; this.env = env;
  }

  public record Owner(String id, String deploymentId, String projectId, String instance,
      String job, long build, long cursor, boolean complete, Instant occurredAt, String stream) {}
  record Block(int start, int end, String text, byte[] bytes) {}
  record Parsed(List<Block> blocks, int consumed, boolean complete) {}

  public List<String> candidates() {
    configured();
    return jdbc.query("""
        select id from jenkins_execution where instance_id=:instance and operation<>'stop'
          and dispatch_status='accepted' and build_number>0 and log_complete=false
          and (log_owner_execution_id is null or log_owner_execution_id=id)
        order by coalesce(last_checked_at,created_at),id limit 8
        """, Map.of("instance", instance()), (rs, row) -> rs.getString(1));
  }

  @Transactional(propagation = Propagation.REQUIRES_NEW)
  public Owner owner(String candidate) {
    configured();
    var row = row(candidate, false);
    lock("project", (String) row.get("project_id"));
    lock("deployment", (String) row.get("deployment_id"));
    require(instance().equals(row.get("instance_id")) && !"stop".equals(row.get("operation"))
        && "accepted".equals(row.get("dispatch_status")) && row.get("build_number") != null, ErrorCode.STATE_CONFLICT);
    String stream = stream(row);
    jdbc.queryForList("select pg_advisory_xact_lock(hashtextextended(:stream,0))", Map.of("stream", stream));
    var p = new MapSqlParameterSource().addValue("instance", row.get("instance_id"))
        .addValue("job", row.get("job_full_name")).addValue("build", row.get("build_number"));
    var owners = jdbc.queryForList("""
        select id,deployment_id from jenkins_execution where instance_id=:instance and job_full_name=:job
          and build_number=:build and log_owner_execution_id=id for update
        """, p);
    require(owners.size() <= 1, ErrorCode.STATE_CONFLICT);
    String owner = owners.isEmpty() ? candidate : (String) owners.getFirst().get("id");
    if (!owners.isEmpty()) require(row.get("deployment_id").equals(owners.getFirst().get("deployment_id")), ErrorCode.STATE_CONFLICT);
    row = row(candidate, true);
    require(stream.equals(stream(row)) && (row.get("log_owner_execution_id") == null
        || owner.equals(row.get("log_owner_execution_id"))), ErrorCode.STATE_CONFLICT);
    jdbc.update("update jenkins_execution set log_owner_execution_id=:owner where id=:id",
        Map.of("owner", owner, "id", candidate));
    return snapshot(row(owner, true), stream);
  }

  /** Cursor and public events either commit together or are retried from the same byte offset. */
  @Transactional(propagation = Propagation.REQUIRES_NEW)
  public boolean commit(Owner owner, LogChunk response) {
    configured();
    Parsed parsed = parse(owner.cursor(), response);
    List<DeploymentEvent> events = new ArrayList<>();
    for (Block block : parsed.blocks()) {
      long start = Math.addExact(owner.cursor(), block.start());
      long end = Math.addExact(owner.cursor(), block.end());
      String digest = json.hash(mapper.valueToTree(Base64.getEncoder().encodeToString(block.bytes())));
      events.add(new DeploymentEvent(owner.stream(), "bytes-" + start + "-" + end, null,
          owner.id(), null, "log.batch", null, null, "info", block.text().isBlank() ? null : block.text(),
          mapper.valueToTree(Map.of("execution_id", owner.id(), "digest", digest)), "applied",
          owner.stream(), start, end, owner.occurredAt()));
    }
    // Check every block before inserting any log rows; the journal owns public-output filtering.
    events.forEach(journal::validate);
    lock("project", owner.projectId()); lock("deployment", owner.deploymentId());
    var row = row(owner.id(), true);
    require(owner.id().equals(row.get("log_owner_execution_id")) && owner.stream().equals(stream(row))
        && owner.deploymentId().equals(row.get("deployment_id"))
        && owner.projectId().equals(row.get("project_id")), ErrorCode.STATE_CONFLICT);
    if (((Number) row.get("log_cursor")).longValue() != owner.cursor() || Boolean.TRUE.equals(row.get("log_complete"))) return false;
    for (DeploymentEvent event : events) journal.appendDeployment(owner.projectId(), owner.deploymentId(), event, false);
    jdbc.update("""
        update jenkins_execution set log_cursor=:cursor,log_complete=:complete,last_checked_at=now()
        where id=:id and log_owner_execution_id=id and log_cursor=:previous
        """, new MapSqlParameterSource().addValue("id", owner.id()).addValue("previous", owner.cursor())
        .addValue("cursor", Math.addExact(owner.cursor(), parsed.consumed())).addValue("complete", parsed.complete()));
    return true;
  }

  @Transactional(propagation = Propagation.REQUIRES_NEW)
  public void failed(String candidate) {
    configured();
    jdbc.update("update jenkins_execution set last_error='console_unconfirmed',last_checked_at=now() where id=:id and instance_id=:instance and dispatch_status='accepted'",
        Map.of("id", candidate, "instance", instance()));
  }

  static Parsed parse(long start, LogChunk response) {
    require(start >= 0 && response != null && response.bytes() != null
        && response.bytes().length <= 1048576 && response.nextOffset() >= start
        && response.nextOffset() - start == response.bytes().length, ErrorCode.STATE_CONFLICT);
    byte[] bytes = response.bytes();
    int consumed = bytes.length;
    if (response.moreData()) {
      consumed = 0;
      for (int i = bytes.length - 1; i >= 0; i--) if (bytes[i] == '\n') { consumed = i + 1; break; }
    }
    // ponytail: one line is at most 16KiB; add an explicit fragment protocol if infra emits larger lines.
    require(bytes.length - consumed <= MESSAGE_BYTES, ErrorCode.VALIDATION_FAILED);
    List<Block> blocks = new ArrayList<>();
    int blockStart = 0, lineStart = 0;
    for (int i = 0; i < consumed; i++) {
      if (bytes[i] != '\n' && i + 1 != consumed) continue;
      int lineEnd = i + 1;
      require(lineEnd - lineStart <= MESSAGE_BYTES, ErrorCode.VALIDATION_FAILED);
      if (lineEnd - blockStart > MESSAGE_BYTES) {
        blocks.add(block(bytes, blockStart, lineStart));
        blockStart = lineStart;
      }
      lineStart = lineEnd;
    }
    if (consumed > blockStart) blocks.add(block(bytes, blockStart, consumed));
    return new Parsed(List.copyOf(blocks), consumed, !response.moreData() && consumed == bytes.length);
  }

  private static Block block(byte[] bytes, int start, int end) {
    byte[] value = Arrays.copyOfRange(bytes, start, end);
    try {
      String text = StandardCharsets.UTF_8.newDecoder().onMalformedInput(CodingErrorAction.REPORT)
          .onUnmappableCharacter(CodingErrorAction.REPORT).decode(ByteBuffer.wrap(value)).toString();
      return new Block(start, end, text, value);
    } catch (java.nio.charset.CharacterCodingException e) { throw new DaisyException(ErrorCode.VALIDATION_FAILED); }
  }

  private Map<String, Object> row(String id, boolean locked) {
    var rows = jdbc.queryForList("select e.*,d.project_id from jenkins_execution e join deployment d on d.id=e.deployment_id where e.id=:id"
        + (locked ? " for update of e" : ""), Map.of("id", id));
    require(rows.size() == 1, ErrorCode.NOT_FOUND);
    return rows.getFirst();
  }

  private String stream(Map<String, Object> row) {
    require(row.get("build_number") instanceof Number && ((Number) row.get("build_number")).longValue() > 0, ErrorCode.STATE_CONFLICT);
    return "jenkins-console:" + json.hash(mapper.valueToTree(Map.of("instance", row.get("instance_id"),
        "job", row.get("job_full_name"), "build", row.get("build_number"))));
  }

  private Owner snapshot(Map<String, Object> row, String stream) {
    return new Owner((String) row.get("id"), (String) row.get("deployment_id"), (String) row.get("project_id"),
        (String) row.get("instance_id"), (String) row.get("job_full_name"), ((Number) row.get("build_number")).longValue(),
        ((Number) row.get("log_cursor")).longValue(), Boolean.TRUE.equals(row.get("log_complete")),
        ((java.sql.Timestamp) row.get("created_at")).toInstant(), stream);
  }
  private String instance() { return env.getProperty("daisy.jenkins.instance-id", "proposal-jenkins"); }
  private void configured() {
    require(env.getProperty("daisy.jenkins.console-enabled", Boolean.class, false)
        && env.getProperty("daisy.jenkins.console-sanitized-utf8-confirmed", Boolean.class, false), ErrorCode.FORBIDDEN);
  }
  private void lock(String table, String id) {
    require(!jdbc.queryForList("select id from " + table + " where id=:id for update", Map.of("id", id)).isEmpty(), ErrorCode.NOT_FOUND);
  }
  private static void require(boolean condition, ErrorCode code) { if (!condition) throw new DaisyException(code); }
}
