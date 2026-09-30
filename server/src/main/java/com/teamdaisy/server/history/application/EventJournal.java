package com.teamdaisy.server.history.application;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.teamdaisy.server.common.error.DaisyException;
import com.teamdaisy.server.common.error.ErrorCode;
import com.teamdaisy.server.common.json.CanonicalJson;
import java.nio.charset.StandardCharsets;
import java.sql.Timestamp;
import java.time.Instant;
import java.util.*;
import java.util.regex.Pattern;
import org.springframework.jdbc.core.namedparam.MapSqlParameterSource;
import org.springframework.jdbc.core.namedparam.NamedParameterJdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;

@Service
@Transactional(readOnly = true)
public class EventJournal {
  public static final int BATCH_SIZE = 100;
  private static final Set<String> TYPES = Set.of("deployment.created", "deployment.state_changed", "deployment.completed",
      "target.status_changed", "step.started", "step.completed", "step.failed", "plan.ready",
      "plan.stale", "approval.required", "approval.resolved", "log.batch", "build.received");
  private static final Set<String> FIELDS = Set.of("deployment_id", "deployment_target_id", "target_id",
      "execution_id", "source_version_id", "plan_id", "approval_id", "status", "state", "step",
      "attempt", "reason", "ai_reused", "revision", "digest", "input_hash", "commit_sha",
      "processing_result", "create", "update", "delete", "has_delete", "expires_at", "request_id", "receipt_hash",
      "duration_ms", "started_at", "stage_occurrence_id");
  private static final Pattern SECRET = Pattern.compile(
      "(?i)(-----BEGIN [A-Z ]*PRIVATE KEY|bearer\\s+|(?:password|secret|token|authorization|credential|access[_-]?key)\\s*[:=]|AKIA[A-Z0-9]{16}|gh[pousr]_[A-Za-z0-9]{20,})");
  private final NamedParameterJdbcTemplate jdbc;
  private final ObjectMapper mapper;
  private final CanonicalJson json;

  public EventJournal(NamedParameterJdbcTemplate jdbc, ObjectMapper mapper, CanonicalJson json) {
    this.jdbc = jdbc; this.mapper = mapper; this.json = json;
  }

  public record AppendResult(long id, long seq, boolean duplicate) {}
  public record PublicEvent(long seq, String deploymentId, String targetId, String eventType, JsonNode payload, String message, String step, String level,
      String processingResult, Instant occurredAt) {}
  public record Bounds(long first, long last) {}
  public record ProjectInput(String source, String sourceEventId, String deploymentId,
      String sourceVersionId, String eventType, JsonNode payload, Instant occurredAt) {}

  @Transactional(propagation = Propagation.MANDATORY)
  public AppendResult appendDeployment(String projectId, String deploymentId,
      DeploymentEvent event, boolean projectProjection) {
    text(projectId,64,false); text(deploymentId,64,false);
    validate(event);
    lock("project", projectId);
    var dep = jdbc.queryForList("select project_id from deployment where id=:id for update", Map.of("id", deploymentId));
    require(dep.size() == 1 && projectId.equals(dep.getFirst().get("project_id")), ErrorCode.NOT_FOUND);
    checkMembership(deploymentId, event);
    var p = new MapSqlParameterSource().addValue("deployment", deploymentId)
        .addValue("source", event.source()).addValue("event", event.sourceEventId());
    String hash = sourceHash(deploymentId, event);
    p.addValue("hash", hash);
    // Stable source locks also serialize duplicates arriving for different deployment rows.
    List<String> identities = new ArrayList<>();
    identities.add("event:" + event.source() + ":" + event.sourceEventId());
    if (event.sourceStream() != null) identities.add("offset:" + event.sourceStream() + ":" + event.sourceOffset());
    identities.stream().sorted().forEach(identity -> jdbc.queryForList(
        "select pg_advisory_xact_lock(hashtextextended(:identity,0))", Map.of("identity", identity)));
    var existing = jdbc.queryForList("select id,seq,payload_hash from deployment_log where source=:source and source_event_id=:event", p);
    if (!existing.isEmpty()) return duplicate(existing.getFirst(), hash);
    if (event.sourceStream() != null) {
      var offset = jdbc.queryForList("select id,seq,payload_hash from deployment_log where source_stream=:stream and source_offset=:offset",
          Map.of("stream", event.sourceStream(), "offset", event.sourceOffset()));
      if (!offset.isEmpty()) return duplicate(offset.getFirst(), hash);
    }
    long seq = next("deployment", deploymentId);
    p.addValue("seq", seq).addValue("execution", event.executionId()).addValue("target", event.deploymentTargetId())
        .addValue("sourceSequence", event.sourceSequence()).addValue("type", event.eventType())
        .addValue("stage", event.stageOccurrenceId()).addValue("step", event.step()).addValue("level", event.level())
        .addValue("message", event.message()).addValue("payload", json.canonicalize(event.payload()))
        .addValue("result", event.processingResult()).addValue("stream", event.sourceStream())
        .addValue("offset", event.sourceOffset()).addValue("endOffset", event.sourceEndOffset())
        .addValue("at", Timestamp.from(event.occurredAt()));
    long id = Objects.requireNonNull(jdbc.queryForObject("""
        insert into deployment_log(deployment_id,execution_id,deployment_target_id,seq,source,source_event_id,
          source_sequence,payload_hash,event_type,stage_occurrence_id,step,level,message,payload,processing_result,
          source_stream,source_offset,source_end_offset,occurred_at,received_at)
        values(:deployment,:execution,:target,:seq,:source,:event,:sourceSequence,:hash,:type,:stage,:step,:level,
          :message,cast(:payload as jsonb),:result,:stream,:offset,:endOffset,:at,now()) returning id
        """, p, Long.class));
    if (projectProjection && "applied".equals(event.processingResult())
        && Set.of("build.received","deployment.created","target.status_changed").contains(event.eventType())) {
      appendProjectRow(projectId, new ProjectInput(event.source(), event.sourceEventId(), deploymentId,
          null, event.eventType(), event.payload(), event.occurredAt()), id);
    }
    return new AppendResult(id, seq, false);
  }

  @Transactional(propagation = Propagation.MANDATORY)
  public AppendResult appendProject(String projectId, ProjectInput event) {
    text(projectId,64,false); require(event!=null,ErrorCode.VALIDATION_FAILED);
    lock("project", projectId);
    return appendProjectRow(projectId, event, null);
  }

  private AppendResult appendProjectRow(String projectId, ProjectInput event, Long logId) {
    text(event.source(),512,false); text(event.sourceEventId(),255,false);
    require(event.eventType()!=null && TYPES.contains(event.eventType()) && event.occurredAt() != null, ErrorCode.VALIDATION_FAILED);
    safePayload(event.payload()); json.copy(mapper.valueToTree(event));
    if (event.deploymentId()!=null) require(count("select count(*) from deployment where id=:id and project_id=:project",
        Map.of("id",event.deploymentId(),"project",projectId))==1,ErrorCode.STATE_CONFLICT);
    if (event.sourceVersionId()!=null) require(count("select count(*) from source_version where id=:id and project_id=:project",
        Map.of("id",event.sourceVersionId(),"project",projectId))==1,ErrorCode.STATE_CONFLICT);
    String hash=json.hash(mapper.valueToTree(event));
    var p=new MapSqlParameterSource().addValue("project",projectId).addValue("source",event.source())
        .addValue("event",event.sourceEventId()).addValue("hash",hash);
    var existing=jdbc.queryForList("select id,seq,payload_hash from project_event where project_id=:project and source=:source and source_event_id=:event",p);
    if(!existing.isEmpty()) return duplicate(existing.getFirst(),hash);
    long seq=next("project",projectId);
    p.addValue("seq",seq).addValue("deployment",event.deploymentId()).addValue("version",event.sourceVersionId())
        .addValue("log",logId).addValue("type",event.eventType()).addValue("payload",json.canonicalize(event.payload()))
        .addValue("at",Timestamp.from(event.occurredAt()));
    long id=Objects.requireNonNull(jdbc.queryForObject("""
        insert into project_event(project_id,deployment_id,source_version_id,deployment_log_id,seq,source,
          source_event_id,payload_hash,event_type,payload,occurred_at,received_at)
        values(:project,:deployment,:version,:log,:seq,:source,:event,:hash,:type,cast(:payload as jsonb),:at,now()) returning id
        """,p,Long.class));
    return new AppendResult(id,seq,false);
  }

  public List<PublicEvent> readDeployment(String id,long cursor) { return read(false,id,cursor); }
  public List<PublicEvent> readProject(String id,long cursor) { return read(true,id,cursor); }
  public Bounds deploymentBounds(String id) { return bounds(false,id); }
  public Bounds projectBounds(String id) { return bounds(true,id); }

  public void requireDeploymentProject(String projectId,String deploymentId) {
    text(projectId,64,false); text(deploymentId,64,false);
    require(count("select count(*) from deployment where id=:id and project_id=:project",
        Map.of("id",deploymentId,"project",projectId))==1,ErrorCode.NOT_FOUND);
  }

  private List<PublicEvent> read(boolean project,String id,long cursor) {
    require(cursor>=0,ErrorCode.VALIDATION_FAILED);
    String table=project?"project_event":"deployment_log", column=project?"project_id":"deployment_id";
    return jdbc.query("select e.seq,e.deployment_id,"+(project?"null":"t.target_id")+" as target_id,e.event_type,e.payload,"+
        (project?"null as message,null as step,null as level,'applied' as processing_result":"e.message,e.step,e.level,e.processing_result")+
        ",e.occurred_at from "+table+" e "+(project?"":"left join deployment_target t on t.id=e.deployment_target_id ")+
        "where e."+column+"=:id and e.seq>:cursor order by e.seq limit "+BATCH_SIZE,
        Map.of("id",id,"cursor",cursor),(rs,row)->new PublicEvent(rs.getLong("seq"),rs.getString("deployment_id"),rs.getString("target_id"),rs.getString("event_type"),
            parse(rs.getString("payload")),rs.getString("message"),rs.getString("step"),rs.getString("level"),rs.getString("processing_result"),rs.getTimestamp("occurred_at").toInstant()));
  }

  private Bounds bounds(boolean project,String id) {
    String table=project?"project_event":"deployment_log", column=project?"project_id":"deployment_id";
    var rows=jdbc.queryForList("select last_event_seq,(select min(seq) from "+table+" where "+column+"=:id) as first from "+
        (project?"project":"deployment")+" where id=:id",Map.of("id",id));
    require(rows.size()==1,ErrorCode.NOT_FOUND);
    var row=rows.getFirst(); long last=((Number)row.get("last_event_seq")).longValue();
    return new Bounds(row.get("first")==null?last+1:((Number)row.get("first")).longValue(),last);
  }

  private void checkMembership(String deployment,DeploymentEvent event) {
    if(event.executionId()!=null) require(count("select count(*) from jenkins_execution where id=:id and deployment_id=:deployment",
        Map.of("id",event.executionId(),"deployment",deployment))==1,ErrorCode.STATE_CONFLICT);
    if(event.deploymentTargetId()!=null) require(count("select count(*) from deployment_target where id=:id and deployment_id=:deployment",
        Map.of("id",event.deploymentTargetId(),"deployment",deployment))==1,ErrorCode.STATE_CONFLICT);
    if(event.executionId()!=null && event.deploymentTargetId()!=null) require(count(
        "select count(*) from execution_target where execution_id=:execution and deployment_target_id=:target",
        Map.of("execution",event.executionId(),"target",event.deploymentTargetId()))==1,ErrorCode.STATE_CONFLICT);
  }
  private long count(String sql,Map<String,?> params) { return Objects.requireNonNull(jdbc.queryForObject(sql,params,Long.class)); }
  private void lock(String table,String id) { require(!jdbc.queryForList("select id from "+table+" where id=:id for update",Map.of("id",id)).isEmpty(),ErrorCode.NOT_FOUND); }
  private long next(String table,String id) { return Objects.requireNonNull(jdbc.queryForObject("update "+table+" set last_event_seq=last_event_seq+1 where id=:id returning last_event_seq",Map.of("id",id),Long.class)); }
  private AppendResult duplicate(Map<String,Object> row,String hash) {
    require(hash.equals(row.get("payload_hash")),ErrorCode.STATE_CONFLICT);
    return new AppendResult(((Number)row.get("id")).longValue(),((Number)row.get("seq")).longValue(),true);
  }
  private JsonNode parse(String body) { try { return mapper.readTree(body); } catch(Exception e) { throw new DaisyException(ErrorCode.INTERNAL); } }

  String sourceHash(String deploymentId, DeploymentEvent event) {
    var source = mapper.<com.fasterxml.jackson.databind.node.ObjectNode>valueToTree(event);
    source.remove(List.of("processing_result", "processingResult"));
    return json.hash(mapper.valueToTree(Map.of("deployment_id",deploymentId,"event",source)));
  }

  public void validate(DeploymentEvent e) {
    require(e!=null,ErrorCode.VALIDATION_FAILED);
    text(e.source(),512,false); text(e.sourceEventId(),255,false); text(e.executionId(),64,true);
    text(e.deploymentTargetId(),64,true); text(e.stageOccurrenceId(),255,true); text(e.sourceStream(),512,true);
    require(e.eventType()!=null && TYPES.contains(e.eventType()) && e.level()!=null && Set.of("debug","info","warn","error").contains(e.level())
        && e.processingResult()!=null && Set.of("applied","ignored_stale").contains(e.processingResult()) && e.occurredAt()!=null,ErrorCode.VALIDATION_FAILED);
    require(e.step()==null || Set.of("generate","validate","plan","risk_check","apply","health_check").contains(e.step()),ErrorCode.VALIDATION_FAILED);
    require(e.sourceSequence()==null || e.sourceSequence()>=0,ErrorCode.VALIDATION_FAILED);
    require(e.sourceStream()==null ? e.sourceOffset()==null && e.sourceEndOffset()==null :
        e.sourceOffset()!=null && e.sourceEndOffset()!=null && e.sourceOffset()>=0 && e.sourceEndOffset()>e.sourceOffset(),ErrorCode.VALIDATION_FAILED);
    text(e.message(),16*1024,true); safePayload(e.payload()); json.copy(mapper.valueToTree(e));
  }
  private void safePayload(JsonNode payload) {
    require(payload!=null && payload.isObject(),ErrorCode.VALIDATION_FAILED);
    payload.fields().forEachRemaining(field -> {
      require(FIELDS.contains(field.getKey()) && field.getValue().isValueNode(),ErrorCode.VALIDATION_FAILED);
      if(field.getValue().isTextual()) text(field.getValue().textValue(),16*1024,true);
    });
  }
  private static void text(String value,int max,boolean nullable) {
    require(value==null ? nullable : !value.isBlank() && value.getBytes(StandardCharsets.UTF_8).length<=max
        && !SECRET.matcher(value).find(),ErrorCode.VALIDATION_FAILED);
  }
  private static void require(boolean condition,ErrorCode error) { if(!condition) throw new DaisyException(error); }
}
