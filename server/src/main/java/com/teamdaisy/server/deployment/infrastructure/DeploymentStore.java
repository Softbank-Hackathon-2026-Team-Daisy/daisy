package com.teamdaisy.server.deployment.infrastructure;

import com.teamdaisy.server.common.error.DaisyException;
import com.teamdaisy.server.common.error.ErrorCode;
import com.teamdaisy.server.deployment.domain.*;
import jakarta.persistence.EntityManager;
import jakarta.persistence.LockModeType;
import java.util.List;
import java.util.Map;
import org.springframework.jdbc.core.namedparam.NamedParameterJdbcTemplate;
import org.springframework.stereotype.Repository;

@Repository
public class DeploymentStore {
  private final EntityManager em;
  private final NamedParameterJdbcTemplate jdbc;
  public DeploymentStore(EntityManager em, NamedParameterJdbcTemplate jdbc) { this.em = em; this.jdbc = jdbc; }
  public void lockProject(String project) {
    if (jdbc.queryForList("select id from project where id=:id for update", Map.of("id", project)).isEmpty())
      throw new DaisyException(ErrorCode.NOT_FOUND);
  }
  public Deployment lock(String project, String id) {
    lockProject(project);
    Deployment value = em.find(Deployment.class, id, LockModeType.PESSIMISTIC_WRITE);
    if (value == null || !project.equals(value.projectId())) throw new DaisyException(ErrorCode.NOT_FOUND);
    return value;
  }
  public List<DeploymentTarget> targets(String deployment) {
    return em.createQuery("select t from DeploymentTarget t where t.deploymentId=:id order by t.id", DeploymentTarget.class)
        .setParameter("id", deployment).setLockMode(LockModeType.PESSIMISTIC_WRITE).getResultList();
  }
  public PlanRevision plan(String id) { return required(PlanRevision.class,id); }
  public Approval approval(String id) { return required(Approval.class,id); }
  public Approval approvalForPlan(String plan) {
    var values = em.createQuery("select a from Approval a where a.planId=:plan", Approval.class)
        .setParameter("plan", plan).setLockMode(LockModeType.PESSIMISTIC_WRITE).getResultList();
    if (values.size()!=1) throw new DaisyException(ErrorCode.NOT_FOUND);
    return values.getFirst();
  }
  public PlanRevision sourcePlan(String source,String id) {
    return em.createQuery("select p from PlanRevision p where p.source=:source and p.sourcePlanId=:id", PlanRevision.class)
        .setParameter("source",source).setParameter("id",id).getResultStream().findFirst().orElse(null);
  }
  public int nextRevision(String target) {
    Number last = em.createQuery("select coalesce(max(p.revision),0) from PlanRevision p where p.deploymentTargetId=:id", Number.class)
        .setParameter("id",target).getSingleResult();
    return Math.addExact(last.intValue(),1);
  }
  private <T> T required(Class<T> type,String id) {
    T value = em.find(type,id,LockModeType.PESSIMISTIC_WRITE);
    if(value==null) throw new DaisyException(ErrorCode.NOT_FOUND);
    return value;
  }
  public void save(Object value) { em.persist(value); }
  public void flush() { em.flush(); }
}
