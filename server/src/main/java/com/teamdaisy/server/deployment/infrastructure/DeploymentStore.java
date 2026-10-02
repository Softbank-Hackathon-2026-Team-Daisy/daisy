package com.teamdaisy.server.deployment.infrastructure;

import com.teamdaisy.server.common.error.DaisyException;
import com.teamdaisy.server.common.error.ErrorCode;
import com.teamdaisy.server.deployment.domain.*;
import jakarta.persistence.EntityManager;
import jakarta.persistence.LockModeType;
import java.sql.Timestamp;
import java.time.Instant;
import java.util.List;
import java.util.Map;
import org.springframework.jdbc.core.namedparam.NamedParameterJdbcTemplate;
import org.springframework.stereotype.Repository;

@Repository
public class DeploymentStore {
  private final EntityManager em;
  private final NamedParameterJdbcTemplate jdbc;

  public DeploymentStore(EntityManager em, NamedParameterJdbcTemplate jdbc) {
    this.em = em;
    this.jdbc = jdbc;
  }

  public void lockProject(String project) {
    if (jdbc.queryForList("select id from project where id=:id for update", Map.of("id", project))
        .isEmpty()) throw new DaisyException(ErrorCode.NOT_FOUND);
  }

  public Deployment lock(String project, String id) {
    lockProject(project);
    Deployment value = em.find(Deployment.class, id, LockModeType.PESSIMISTIC_WRITE);
    if (value == null || !project.equals(value.projectId()))
      throw new DaisyException(ErrorCode.NOT_FOUND);
    return value;
  }

  public List<DeploymentTarget> targets(String deployment) {
    return em.createQuery(
            "select t from DeploymentTarget t where t.deploymentId=:id order by t.id",
            DeploymentTarget.class)
        .setParameter("id", deployment)
        .setLockMode(LockModeType.PESSIMISTIC_WRITE)
        .getResultList();
  }

  public PlanRevision plan(String id) {
    return required(PlanRevision.class, id);
  }

  public Approval approval(String id) {
    return required(Approval.class, id);
  }

  public Approval approvalForPlan(String plan) {
    var values =
        em.createQuery("select a from Approval a where a.planId=:plan", Approval.class)
            .setParameter("plan", plan)
            .setLockMode(LockModeType.PESSIMISTIC_WRITE)
            .getResultList();
    if (values.size() != 1) throw new DaisyException(ErrorCode.NOT_FOUND);
    return values.getFirst();
  }

  public PlanRevision sourcePlan(String source, String id) {
    return em.createQuery(
            "select p from PlanRevision p where p.source=:source and p.sourcePlanId=:id",
            PlanRevision.class)
        .setParameter("source", source)
        .setParameter("id", id)
        .getResultStream()
        .findFirst()
        .orElse(null);
  }

  public int nextRevision(String target) {
    Number last =
        em.createQuery(
                "select coalesce(max(p.revision),0) from PlanRevision p where p.deploymentTargetId=:id",
                Number.class)
            .setParameter("id", target)
            .getSingleResult();
    return Math.addExact(last.intValue(), 1);
  }

  private <T> T required(Class<T> type, String id) {
    T value = em.find(type, id, LockModeType.PESSIMISTIC_WRITE);
    if (value == null) throw new DaisyException(ErrorCode.NOT_FOUND);
    return value;
  }

  public void save(Object value) {
    em.persist(value);
  }

  public void flush() {
    em.flush();
  }

  /**
   * Called after success validation/flush, under the project lock and before state lock release.
   */
  public void recordSuccessfulTarget(String deploymentTargetId, Instant receivedAt) {
    jdbc.update(
        """
        update target t set current_deployment_target_id=d.id, connection_state='connected',
          connection_checked_at=:at, updated_at=:at
        from deployment_target d
        where d.id=:id and d.status='succeeded' and d.finished_at is not null
          and t.id=d.target_id and t.project_id=d.project_id and t.archived_at is null
          and t.state_identity=d.state_identity
          and to_jsonb(t.config_revision)=d.target_snapshot->'config_revision'
          and t.credential_ref is not distinct from d.target_snapshot->>'credential_ref'
          and t.credential_version is not distinct from d.target_snapshot->>'credential_version'
          and exists(select 1 from project p where p.id=t.project_id and p.archived_at is null)
          and exists(select 1 from target_lock l where l.state_identity=d.state_identity
            and l.execution_id=d.current_execution_id and l.deployment_target_id=d.id)
        """,
        Map.of("id", deploymentTargetId, "at", Timestamp.from(receivedAt)));
  }

  public record ExpiredApproval(String projectId, String deploymentId, String deploymentTargetId) {}

  public List<ExpiredApproval> expiredApprovals() {
    return jdbc.query(
        """
        select t.project_id, t.deployment_id, t.id
        from deployment_target t
        join approval a on a.plan_id=t.current_plan_id and a.deployment_target_id=t.id
        join jenkins_execution j on j.id=t.current_execution_id
        join execution_target et on et.execution_id=j.id and et.deployment_target_id=t.id
        where t.status='awaiting_approval' and a.state='pending' and a.expires_at<=now()
          and j.operation in ('prepare','replan')
          and (j.run_status in ('succeeded','failed','cancelled')
               or (et.status in ('succeeded','failed','cancelled','stale') and et.finished_at is not null))
        order by a.expires_at, a.id limit 100
        """,
        Map.of(),
        (rs, row) ->
            new ExpiredApproval(
                rs.getString("project_id"), rs.getString("deployment_id"), rs.getString("id")));
  }
}
