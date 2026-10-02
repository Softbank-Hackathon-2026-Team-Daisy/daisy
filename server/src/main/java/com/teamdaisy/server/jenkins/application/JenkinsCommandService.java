package com.teamdaisy.server.jenkins.application;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ObjectNode;
import com.teamdaisy.server.common.error.DaisyException;
import com.teamdaisy.server.common.error.ErrorCode;
import com.teamdaisy.server.common.json.CanonicalJson;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.sql.Timestamp;
import java.time.Instant;
import java.util.Comparator;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.Set;
import java.util.UUID;
import org.springframework.core.env.Environment;
import org.springframework.jdbc.core.namedparam.MapSqlParameterSource;
import org.springframework.jdbc.core.namedparam.NamedParameterJdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;

@Service
@Transactional(readOnly = true)
public class JenkinsCommandService {
  private final NamedParameterJdbcTemplate jdbc;
  private final ObjectMapper mapper;
  private final CanonicalJson json;
  private final Environment env;

  public JenkinsCommandService(
      NamedParameterJdbcTemplate jdbc, ObjectMapper mapper, CanonicalJson json, Environment env) {
    this.jdbc = jdbc;
    this.mapper = mapper;
    this.json = json;
    this.env = env;
  }

  public record CommandTarget(
      String deploymentTargetId,
      String inputHash,
      String planId,
      String planDigest,
      String stateIdentity) {}

  public record CommandRef(String id, String requestId) {}

  public record CommandScope(
      String id,
      String deploymentId,
      String projectId,
      String requestId,
      String operation,
      String parentExecutionId,
      String instanceId,
      String jobFullName,
      String dispatchStatus,
      String runStatus,
      Long queueId,
      Long buildNumber,
      JsonNode payload) {}

  @Transactional(propagation = Propagation.MANDATORY)
  public CommandRef enqueue(
      String deploymentId,
      String operation,
      String parentExecutionId,
      List<CommandTarget> targets,
      JsonNode payload) {
    require(
        operation != null && Set.of("prepare", "replan", "apply", "stop").contains(operation),
        ErrorCode.VALIDATION_FAILED);
    require(targets != null && payload != null && payload.isObject(), ErrorCode.VALIDATION_FAILED);
    var deployment =
        jdbc.queryForList(
            "select project_id from deployment where id=:id", Map.of("id", deploymentId));
    require(deployment.size() == 1, ErrorCode.NOT_FOUND);
    String project = (String) deployment.getFirst().get("project_id");
    lock("project", project);
    lock("deployment", deploymentId);
    if (parentExecutionId != null)
      require(
          lookup(parentExecutionId).deploymentId().equals(deploymentId), ErrorCode.STATE_CONFLICT);
    require(!operation.equals("stop") || parentExecutionId != null, ErrorCode.STATE_CONFLICT);
    require(
        targets.size() <= 100
            && targets.stream().allMatch(t -> t != null && t.deploymentTargetId() != null),
        ErrorCode.VALIDATION_FAILED);
    List<CommandTarget> ordered =
        targets.stream().sorted(Comparator.comparing(CommandTarget::deploymentTargetId)).toList();
    require(
        ordered.stream().map(CommandTarget::deploymentTargetId).distinct().count()
            == ordered.size(),
        ErrorCode.VALIDATION_FAILED);
    require(!operation.equals("apply") || !ordered.isEmpty(), ErrorCode.VALIDATION_FAILED);
    var states = new HashSet<String>();
    for (CommandTarget target : ordered) {
      require(target.deploymentTargetId() != null, ErrorCode.VALIDATION_FAILED);
      var rows =
          jdbc.queryForList(
              "select input_hash,state_identity,current_plan_id from deployment_target where id=:id and deployment_id=:deployment for update",
              Map.of("id", target.deploymentTargetId(), "deployment", deploymentId));
      require(rows.size() == 1, ErrorCode.STATE_CONFLICT);
      var row = rows.getFirst();
      require(
          Objects.equals(target.stateIdentity(), row.get("state_identity")),
          ErrorCode.STATE_CONFLICT);
      require(
          (target.planId() == null) == (target.planDigest() == null), ErrorCode.VALIDATION_FAILED);
      if (operation.equals("stop")) {
        requireScope(parentExecutionId, deploymentId, target.deploymentTargetId());
        require(
            Set.of("prepare", "replan").contains(lookup(parentExecutionId).operation()),
            ErrorCode.STATE_CONFLICT);
      } else {
        require(
            Objects.equals(target.inputHash(), row.get("input_hash")), ErrorCode.STATE_CONFLICT);
        require(operation.equals("apply") || target.planId() == null, ErrorCode.VALIDATION_FAILED);
      }
      if (operation.equals("apply")) {
        require(
            target.inputHash() != null
                && target.planId() != null
                && target.planDigest() != null
                && target.planId().equals(row.get("current_plan_id"))
                && states.add(target.stateIdentity()),
            ErrorCode.STATE_CONFLICT);
        var p =
            new MapSqlParameterSource()
                .addValue("plan", target.planId())
                .addValue("target", target.deploymentTargetId())
                .addValue("digest", target.planDigest())
                .addValue("input", target.inputHash());
        require(
            count(
                    """
            select count(*) from plan_revision p join approval a on a.plan_id=p.id
              join deployment_target t on t.id=p.deployment_target_id
            where p.id=:plan and p.deployment_target_id=:target and p.state='active'
              and p.digest=:digest and p.input_hash=:input and p.expires_at>now()
              and a.deployment_target_id=:target and a.state='approved' and a.decision='approved'
              and a.expires_at>now() and a.expires_at<=p.expires_at
              and a.decided_by is not null and a.decided_at is not null
              and (coalesce((p.summary->>'has_delete')::boolean,false)=false
                or (a.confirmation_text is not null and btrim(a.confirmation_text)<>''))
            """,
                    p)
                == 1,
            ErrorCode.STATE_CONFLICT);
      }
    }
    String id = "job_" + UUID.randomUUID();
    String requestId = UUID.randomUUID().toString();
    String instance = instance();
    String defaultJob =
        switch (operation) {
          case "prepare", "replan" -> "daisy-cd-plan";
          case "apply" -> "daisy-cd-apply";
          default -> "internal-stop"; // STOP uses its parent's run, never submits this Job.
        };
    String job = env.getProperty("daisy.jenkins.operation-jobs." + operation, defaultJob);
    require(
        !instance.isBlank() && instance.length() <= 128 && !job.isBlank() && job.length() <= 512,
        ErrorCode.VALIDATION_FAILED);
    ObjectNode command = (ObjectNode) json.copy(payload);
    command
        .put("request_id", requestId)
        .put("execution_id", id)
        .put("deployment_id", deploymentId)
        .put("operation", operation);
    if (parentExecutionId != null) command.put("parent_execution_id", parentExecutionId);
    else command.remove("parent_execution_id");
    command.set("command_targets", mapper.valueToTree(ordered));
    var p =
        new MapSqlParameterSource()
            .addValue("id", id)
            .addValue("deployment", deploymentId)
            .addValue("request", requestId)
            .addValue("operation", operation)
            .addValue("parent", parentExecutionId)
            .addValue("instance", instance)
            .addValue("job", job)
            .addValue("payload", json.canonicalize(command))
            .addValue("hash", json.hash(command));
    jdbc.update(
        """
        insert into jenkins_execution(id,deployment_id,request_id,operation,parent_execution_id,instance_id,
          job_full_name,request_payload,request_hash,dispatch_status,run_status,dispatch_attempts,
          log_cursor,log_complete,created_at)
        values(:id,:deployment,:request,:operation,:parent,:instance,:job,cast(:payload as jsonb),:hash,
          'pending','unknown',0,0,false,now())
        """,
        p);
    for (CommandTarget target : ordered) {
      p.addValue("target", target.deploymentTargetId())
          .addValue("input", target.inputHash())
          .addValue("plan", target.planId())
          .addValue("digest", target.planDigest());
      jdbc.update(
          """
          insert into execution_target(execution_id,deployment_target_id,deployment_id,input_hash,
            plan_id,plan_digest,status) values(:id,:target,:deployment,:input,:plan,:digest,'pending')
          """,
          p);
    }
    if (operation.equals("apply")) {
      for (CommandTarget target :
          ordered.stream().sorted(Comparator.comparing(CommandTarget::stateIdentity)).toList()) {
        p.addValue("state", target.stateIdentity()).addValue("target", target.deploymentTargetId());
        require(
            jdbc.update(
                    """
            insert into target_lock(state_identity,execution_id,deployment_target_id,acquired_at)
            values(:state,:id,:target,now()) on conflict do nothing
            """,
                    p)
                == 1,
            ErrorCode.TARGET_LOCKED);
      }
    }
    return new CommandRef(id, requestId);
  }

  public CommandScope lookup(String id) {
    var rows =
        jdbc.query(
            "select e.*,d.project_id from jenkins_execution e join deployment d on d.id=e.deployment_id where e.id=:id",
            Map.of("id", id),
            this::scope);
    require(rows.size() == 1, ErrorCode.NOT_FOUND);
    return rows.getFirst();
  }

  public List<CommandTarget> executionTargets(String id) {
    return jdbc.query(
        """
        select e.deployment_target_id,e.input_hash,e.plan_id,e.plan_digest,t.state_identity
        from execution_target e join deployment_target t on t.id=e.deployment_target_id
        where e.execution_id=:id order by e.deployment_target_id
        """,
        Map.of("id", id),
        (rs, i) ->
            new CommandTarget(
                rs.getString(1),
                rs.getString(2),
                rs.getString(3),
                rs.getString(4),
                rs.getString(5)));
  }

  public CommandScope requireScope(String executionId, String deploymentId, String targetId) {
    CommandScope scope = lookup(executionId);
    require(scope.deploymentId().equals(deploymentId), ErrorCode.STATE_CONFLICT);
    if (targetId != null)
      require(
          count(
                  "select count(*) from execution_target where execution_id=:execution and deployment_target_id=:target",
                  new MapSqlParameterSource()
                      .addValue("execution", executionId)
                      .addValue("target", targetId))
              == 1,
          ErrorCode.STATE_CONFLICT);
    return scope;
  }

  /** Authenticated callback binding and its receipt share the caller's transaction. */
  @Transactional(propagation = Propagation.MANDATORY)
  public CommandScope bindCallback(
      String id,
      String requestId,
      String instanceId,
      String job,
      Long queue,
      long build,
      String targetId) {
    require(build > 0 && (queue == null || queue > 0), ErrorCode.VALIDATION_FAILED);
    CommandScope scope = lookup(id);
    lock("project", scope.projectId());
    lock("deployment", scope.deploymentId());
    jdbc.queryForList(
        "select id from deployment_target where deployment_id=:deployment order by id for update",
        Map.of("deployment", scope.deploymentId()));
    lock("jenkins_execution", id);
    scope = requireScope(id, scope.deploymentId(), targetId);
    require(
        scope.requestId().equals(requestId)
            && scope.instanceId().equals(instanceId)
            && scope.jobFullName().equals(job),
        ErrorCode.FORBIDDEN);
    require(!scope.operation().equals("stop"), ErrorCode.STATE_CONFLICT);
    require(
        Set.of("dispatching", "unknown", "accepted").contains(scope.dispatchStatus()),
        ErrorCode.STATE_CONFLICT);
    assertBound(id, queue, build);
    jdbc.update(
        """
        update jenkins_execution set dispatch_status='accepted',queue_id=coalesce(queue_id,:queue),
          build_number=coalesce(build_number,:build),next_check_at=case
            when run_status in ('succeeded','failed','cancelled') then next_check_at else now() end
        where id=:id
        """,
        new MapSqlParameterSource()
            .addValue("id", id)
            .addValue("queue", queue)
            .addValue("build", build));
    return scope;
  }

  @Transactional(propagation = Propagation.MANDATORY)
  public void recordTargetState(
      String executionId,
      String targetId,
      String status,
      long sequence,
      Instant now,
      boolean terminal) {
    require(
        status != null
            && Set.of(
                    "waiting",
                    "generating",
                    "validating",
                    "awaiting_approval",
                    "applying",
                    "verifying",
                    "succeeded",
                    "failed",
                    "cancelled",
                    "stale")
                .contains(status)
            && sequence >= 0
            && now != null,
        ErrorCode.VALIDATION_FAILED);
    boolean finished = Set.of("succeeded", "failed", "cancelled", "stale").contains(status);
    require(terminal == finished, ErrorCode.VALIDATION_FAILED);
    String runState = finished ? status : status.equals("waiting") ? "pending" : "running";
    requireScope(executionId, lookup(executionId).deploymentId(), targetId);
    require(
        jdbc.update(
                """
        update execution_target set status=:status,last_source_sequence=:sequence,
          started_at=coalesce(started_at,:at),finished_at=case when :terminal then :at else finished_at end
        where execution_id=:execution and deployment_target_id=:target
          and (last_source_sequence is null or last_source_sequence<:sequence)
          and finished_at is null
        """,
                new MapSqlParameterSource()
                    .addValue("status", runState)
                    .addValue("sequence", sequence)
                    .addValue("at", Timestamp.from(now))
                    .addValue("terminal", terminal)
                    .addValue("execution", executionId)
                    .addValue("target", targetId))
            == 1,
        ErrorCode.STATE_CONFLICT);
  }

  public boolean targetFinished(String executionId, String targetId) {
    requireScope(executionId, lookup(executionId).deploymentId(), targetId);
    return !jdbc.queryForList(
            """
        select 1 from execution_target where execution_id=:execution and deployment_target_id=:target
          and status in ('succeeded','failed','cancelled','stale') and finished_at is not null
        """,
            Map.of("execution", executionId, "target", targetId))
        .isEmpty();
  }

  @Transactional(propagation = Propagation.MANDATORY)
  public boolean cancelPending(String id) {
    return jdbc.update(
            "update jenkins_execution set dispatch_status='rejected',run_status='cancelled',finished_at=now(),last_error='cancelled_before_dispatch' where id=:id and dispatch_status='pending'",
            Map.of("id", id))
        == 1;
  }

  /** Caller must first append authenticated, applied termination evidence in this transaction. */
  @Transactional(propagation = Propagation.MANDATORY)
  public void releaseOwnedLock(String executionId, String targetId, String source, String eventId) {
    CommandScope scope = requireScope(executionId, lookup(executionId).deploymentId(), targetId);
    lock("project", scope.projectId());
    lock("deployment", scope.deploymentId());
    lock("deployment_target", targetId);
    var p =
        new MapSqlParameterSource()
            .addValue("execution", executionId)
            .addValue("target", targetId)
            .addValue("source", source)
            .addValue("event", eventId);
    require(
        count(
                """
        select count(*) from deployment_log l join execution_target et
          on et.execution_id=l.execution_id and et.deployment_target_id=l.deployment_target_id
        where l.execution_id=:execution and l.deployment_target_id=:target and l.source=:source
          and l.source_event_id=:event and l.processing_result='applied'
          and ((et.status in ('succeeded','failed','cancelled','stale') and et.finished_at is not null
            and l.payload->>'status' in ('succeeded','failed','cancelled','stale'))
          or (l.payload->>'reason' in ('confirmed_not_submitted','confirmed_dispatch_rejected')
            and exists(select 1 from jenkins_execution e where e.id=:execution and e.dispatch_status='rejected')))
        """,
                p)
            == 1,
        ErrorCode.STATE_CONFLICT);
    jdbc.update(
        "delete from target_lock where execution_id=:execution and deployment_target_id=:target",
        p);
  }

  String instance() {
    return env.getProperty("daisy.jenkins.instance-id", "proposal-jenkins");
  }

  @Transactional(propagation = Propagation.REQUIRES_NEW)
  public void recoverDispatching() {
    // ponytail: one BE worker; use coordinated worker ownership before running multiple instances.
    jdbc.update(
        "update jenkins_execution set dispatch_status='unknown',next_check_at=now(),last_error='dispatch_interrupted' where instance_id=:instance and dispatch_status='dispatching'",
        Map.of("instance", instance()));
  }

  @Transactional(propagation = Propagation.REQUIRES_NEW)
  public CommandScope claimPending() {
    var rows =
        jdbc.queryForList(
            "select id from jenkins_execution where instance_id=:instance and dispatch_status='pending' order by created_at,id limit 1",
            Map.of("instance", instance()));
    if (rows.isEmpty()) return null;
    String id = (String) rows.getFirst().get("id");
    CommandScope command = lookup(id);
    lock("project", command.projectId());
    lock("deployment", command.deploymentId());
    List<CommandTarget> targets = executionTargets(id);
    targets.forEach(target -> lock("deployment_target", target.deploymentTargetId()));
    if (jdbc.queryForList(
            "select id from jenkins_execution where id=:id and dispatch_status='pending' for update skip locked",
            Map.of("id", id))
        .isEmpty()) return null;
    if (command.operation().equals("apply") && !applyStillApproved(id, targets.size())) {
      jdbc.update(
          """
          update jenkins_execution set dispatch_status='rejected',last_error='approval_invalid_before_dispatch',
            next_check_at=now() where id=:id and dispatch_status='pending'
          """,
          Map.of("id", id));
      return lookup(id);
    }
    jdbc.update(
        "update jenkins_execution set dispatch_status='dispatching',dispatch_started_at=now(),dispatch_attempts=dispatch_attempts+1 where id=:id",
        Map.of("id", id));
    return lookup(id);
  }

  private boolean applyStillApproved(String id, int targets) {
    return targets > 0
        && count(
                """
        select count(*) from execution_target e join deployment_target t on t.id=e.deployment_target_id
          join plan_revision p on p.id=e.plan_id and p.deployment_target_id=t.id
          join approval a on a.plan_id=p.id and a.deployment_target_id=t.id
          join target_lock l on l.execution_id=e.execution_id and l.deployment_target_id=t.id
        where e.execution_id=:id and t.current_execution_id=:id and t.current_plan_id=p.id
          and e.input_hash=t.input_hash and e.input_hash=p.input_hash and e.plan_digest=p.digest
          and l.state_identity=t.state_identity and p.state='active' and p.expires_at>now()
          and a.state='approved' and a.decision='approved' and a.expires_at>now()
          and a.expires_at<=p.expires_at and a.decided_by is not null and a.decided_at is not null
          and (coalesce((p.summary->>'has_delete')::boolean,false)=false
            or (a.confirmation_text is not null and btrim(a.confirmation_text)<>''))
        """,
                new MapSqlParameterSource("id", id))
            == targets;
  }

  public String rejectionReason(String id) {
    String error =
        jdbc.queryForObject(
            "select last_error from jenkins_execution where id=:id and dispatch_status='rejected'",
            Map.of("id", id),
            String.class);
    return "approval_invalid_before_dispatch".equals(error)
        ? "confirmed_not_submitted"
        : "confirmed_dispatch_rejected";
  }

  @Transactional(propagation = Propagation.REQUIRES_NEW)
  public CommandScope claimCheck() {
    var rows =
        jdbc.queryForList(
            """
        select id from jenkins_execution e where instance_id=:instance
          and (dispatch_status='unknown'
            or (dispatch_status='accepted' and run_status in ('unknown','queued','running'))
            or (dispatch_status='accepted' and run_status='cancelled' and queue_id is not null
              and build_number is null and exists(select 1 from execution_target t
                where t.execution_id=e.id and t.status in ('pending','running')))
            or (dispatch_status='rejected' and last_error in ('dispatch_rejected','approval_invalid_before_dispatch') and operation<>'stop'
              and exists(select 1 from execution_target t where t.execution_id=e.id and t.status in ('pending','running'))))
          and next_check_at<=now()
        order by next_check_at,id limit 1 for update skip locked
        """,
            Map.of("instance", instance()));
    if (rows.isEmpty()) return null;
    String id = (String) rows.getFirst().get("id");
    jdbc.update(
        "update jenkins_execution set next_check_at=now()+interval '60 seconds' where id=:id",
        Map.of("id", id));
    return lookup(id);
  }

  @Transactional(propagation = Propagation.REQUIRES_NEW)
  public void dispatched(String id, Long queue, Long build, String runStatus) {
    require(
        (queue == null || queue > 0) && (build == null || build > 0), ErrorCode.VALIDATION_FAILED);
    require(
        runStatus != null
            && Set.of("unknown", "queued", "running", "succeeded", "failed", "cancelled")
                .contains(runStatus),
        ErrorCode.VALIDATION_FAILED);
    assertBound(id, queue, build);
    jdbc.update(
        """
        update jenkins_execution set dispatch_status='accepted',queue_id=coalesce(queue_id,:queue),build_number=coalesce(build_number,:build),
          run_status=case when run_status in ('succeeded','failed','cancelled') then run_status
            when run_status='running' and :run in ('queued','unknown') then run_status else :run end,
          next_check_at=case when run_status in ('succeeded','failed','cancelled') or :run='unknown'
            then null else now()+interval '5 seconds' end,
          last_checked_at=now(),last_error=null where id=:id and dispatch_status in ('dispatching','unknown','accepted')
        """,
        new MapSqlParameterSource()
            .addValue("id", id)
            .addValue("queue", queue)
            .addValue("build", build)
            .addValue("run", runStatus));
  }

  @Transactional(propagation = Propagation.REQUIRES_NEW)
  public void dispatchFailed(String id, boolean rejected) {
    jdbc.update(
        """
        update jenkins_execution set dispatch_status=:status,last_error=:error,
          next_check_at=now()+interval '5 seconds'
        where id=:id and dispatch_status='dispatching'
        """,
        Map.of(
            "id",
            id,
            "status",
            rejected ? "rejected" : "unknown",
            "error",
            rejected ? "dispatch_rejected" : "dispatch_unconfirmed"));
  }

  @Transactional(propagation = Propagation.REQUIRES_NEW)
  public void observed(String id, Long build, String status) {
    require(
        status != null
            && Set.of("queued", "running", "succeeded", "failed", "cancelled").contains(status)
            && (build == null || build > 0),
        ErrorCode.VALIDATION_FAILED);
    assertBound(id, null, build);
    jdbc.update(
        """
        update jenkins_execution set build_number=coalesce(build_number,:build),
          run_status=case when run_status='running' and :status='queued' then run_status else :status end,
          last_checked_at=now(),last_error=null,
          started_at=case when :status='running' then coalesce(started_at,now()) else started_at end,
          finished_at=case when :status in ('succeeded','failed','cancelled') then coalesce(finished_at,now()) else finished_at end,
          next_check_at=case when :status='cancelled' and cast(:build as bigint) is null and build_number is null then now()
            when :status in ('succeeded','failed','cancelled') then null else now()+interval '5 seconds' end
        where id=:id and dispatch_status='accepted' and run_status in ('unknown','queued','running')
        """,
        new MapSqlParameterSource()
            .addValue("id", id)
            .addValue("build", build)
            .addValue("status", status));
  }

  @Transactional(propagation = Propagation.REQUIRES_NEW)
  public void checkUnconfirmed(String id, String error) {
    require(
        Set.of("lookup_unknown", "lookup_ambiguous", "lookup_unconfirmed").contains(error),
        ErrorCode.VALIDATION_FAILED);
    jdbc.update(
        "update jenkins_execution set last_checked_at=now(),last_error=:error,next_check_at=now()+interval '15 seconds' where id=:id and dispatch_status in ('unknown','accepted')",
        Map.of("id", id, "error", error));
  }

  private CommandScope scope(ResultSet rs, int row) throws SQLException {
    try {
      return new CommandScope(
          rs.getString("id"),
          rs.getString("deployment_id"),
          rs.getString("project_id"),
          rs.getString("request_id"),
          rs.getString("operation"),
          rs.getString("parent_execution_id"),
          rs.getString("instance_id"),
          rs.getString("job_full_name"),
          rs.getString("dispatch_status"),
          rs.getString("run_status"),
          (Long) rs.getObject("queue_id"),
          (Long) rs.getObject("build_number"),
          mapper.readTree(rs.getString("request_payload")));
    } catch (java.io.IOException e) {
      throw new DaisyException(ErrorCode.INTERNAL);
    }
  }

  private void assertBound(String id, Long queue, Long build) {
    var rows =
        jdbc.queryForList(
            "select queue_id,build_number from jenkins_execution where id=:id for update",
            Map.of("id", id));
    require(rows.size() == 1, ErrorCode.NOT_FOUND);
    var row = rows.getFirst();
    require(
        (queue == null
                || row.get("queue_id") == null
                || queue.equals(((Number) row.get("queue_id")).longValue()))
            && (build == null
                || row.get("build_number") == null
                || build.equals(((Number) row.get("build_number")).longValue())),
        ErrorCode.STATE_CONFLICT);
  }

  private long count(String sql, MapSqlParameterSource p) {
    return Objects.requireNonNull(jdbc.queryForObject(sql, p, Long.class));
  }

  private void lock(String table, String id) {
    require(
        !jdbc.queryForList("select id from " + table + " where id=:id for update", Map.of("id", id))
            .isEmpty(),
        ErrorCode.NOT_FOUND);
  }

  private static void require(boolean condition, ErrorCode code) {
    if (!condition) throw new DaisyException(code);
  }
}
