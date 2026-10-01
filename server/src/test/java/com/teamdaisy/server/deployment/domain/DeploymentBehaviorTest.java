package com.teamdaisy.server.deployment.domain;

import static org.junit.jupiter.api.Assertions.*;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ObjectNode;
import com.teamdaisy.server.common.error.DaisyException;
import java.time.Instant;
import java.util.List;
import org.junit.jupiter.api.Test;

class DeploymentBehaviorTest {
  private final ObjectMapper mapper = new ObjectMapper();
  private final Instant now = Instant.parse("2026-10-01T00:00:00Z");
  private final String hash = "sha256:" + "a".repeat(64);
  private final String commit = "b".repeat(40);

  private Deployment deployment(String id) {
    return Deployment.create(
        id,
        "prj_1",
        "actor_1",
        commit,
        mapper.createObjectNode(),
        mapper.createObjectNode().put("hash_format_version", 1),
        hash,
        now);
  }

  private DeploymentTarget target(Deployment deployment, String id) {
    return DeploymentTarget.create(
        id,
        deployment,
        "tgt_" + id,
        mapper.createObjectNode().put("name", "production"),
        "state/" + id);
  }

  private PlanRevision plan(DeploymentTarget target, boolean deletion) {
    ObjectNode summary = mapper.createObjectNode().put("has_delete", deletion);
    summary.set(
        "counts",
        mapper
            .createObjectNode()
            .put("create", 0)
            .put("update", 0)
            .put("delete", deletion ? 1 : 0));
    summary.putArray("risks");
    return PlanRevision.create(
        "plan_" + target.id(),
        target.id(),
        "job_1",
        target.projectId(),
        target.targetId(),
        1,
        "instance/job/1",
        "source_" + target.id(),
        hash,
        "script_1",
        "artifact/plan",
        hash,
        summary,
        mapper.createArrayNode(),
        now,
        now.plusSeconds(600),
        now.plusSeconds(1200));
  }

  private void awaitPlan(DeploymentTarget target, PlanRevision plan) {
    target.bindInput(hash);
    target.attachExecution("job_1");
    target.applyStatus("job_1", 1, DeploymentTargetStatus.VALIDATING, 1, null, null, now);
    target.adoptPlan(plan, now);
  }

  @Test
  void sourceAndSnapshotsAreFrozen() {
    var deployment = deployment("dep_1");
    var images = mapper.createObjectNode();
    images.set(
        "app",
        mapper
            .createObjectNode()
            .put("commit_sha", commit)
            .put("image_ref", "registry/app:" + commit));
    deployment.bindSource("src_1", commit, images, hash);
    deployment.bindSource("src_1", commit, images, hash);
    assertThrows(DaisyException.class, () -> deployment.bindSource("src_2", commit, images, hash));
    images.remove("app");
    assertTrue(deployment.imageRefs().has("app"));
    ((ObjectNode) deployment.inputSnapshot()).put("hash_format_version", 2);
    assertEquals(1, deployment.inputSnapshot().path("hash_format_version").asInt());
  }

  @Test
  void sourceOrderAndCommandOwnershipOverrideStageRankAndStopDoesNotFinish() {
    var target = target(deployment("dep_1"), "dt_1");
    target.attachExecution("job_1");
    assertTrue(
        target.applyStatus("job_1", 2, DeploymentTargetStatus.VALIDATING, 1, null, null, now));
    assertFalse(
        target.applyStatus("job_1", 1, DeploymentTargetStatus.GENERATING, 1, null, null, now));
    assertTrue(
        target.applyStatus("job_1", 3, DeploymentTargetStatus.GENERATING, 2, null, null, now));
    target.requestCancellation("actor_1", now);
    assertEquals("job_1", target.currentExecutionId());
    assertFalse(target.status().terminal());
    target.attachExecution("job_2");
    assertFalse(
        target.applyStatus("job_1", 99, DeploymentTargetStatus.FAILED, 3, "late", null, now));
    assertThrows(
        DaisyException.class,
        () ->
            target.applyStatus("job_2", 1, DeploymentTargetStatus.VALIDATING, 4, null, null, now));
    assertTrue(
        target.applyStatus("job_2", 1, DeploymentTargetStatus.FAILED, 3, "failed", null, now));
    assertFalse(
        target.applyStatus("job_2", 2, DeploymentTargetStatus.GENERATING, 3, null, null, now));
  }

  @Test
  void approvalBindsExactCurrentPlanAndKeepsOriginalDecisionAfterStale() {
    var target = target(deployment("dep_1"), "dt_1");
    var plan = plan(target, true);
    awaitPlan(target, plan);
    var approval = Approval.pending("apv_1", plan, now, now.plusSeconds(500));
    assertThrows(
        DaisyException.class, () -> approval.decide(plan, target, "actor_1", true, "wrong", now));
    approval.decide(plan, target, "actor_1", true, "production", now);
    approval.assertApproved(plan, target, now);
    assertThrows(
        DaisyException.class,
        () -> plan.assertUsable(plan.id(), "sha256:" + "c".repeat(64), hash, now));
    assertThrows(
        DaisyException.class, () -> plan.assertUsable(plan.id(), hash, hash, plan.expiresAt()));
    plan.invalidate("stale", now.plusSeconds(1));
    approval.invalidate("stale", now.plusSeconds(1));
    target.clearPlanForReplan(now.plusSeconds(1));
    assertEquals("approved", approval.decision());
    assertEquals("actor_1", approval.decidedBy());
    assertEquals("superseded", approval.state());
    assertEquals(1, target.attempt());
    assertThrows(DaisyException.class, () -> approval.assertApproved(plan, target, now));
  }

  @Test
  void aggregateKeepsOtherApprovalThenProducesPartialSuccessAndRetryLineage() {
    var deployment = deployment("dep_1");
    var failed = target(deployment, "failed");
    var success = target(deployment, "success");
    failed.attachExecution("job_1");
    failed.applyStatus("job_1", 1, DeploymentTargetStatus.FAILED, 3, "failure", null, now);
    var plan = plan(success, false);
    awaitPlan(success, plan);
    deployment.aggregate(List.of(failed, success), now);
    assertEquals(DeploymentStatus.AWAITING_APPROVAL, deployment.status());
    success.applyStatus("job_1", 2, DeploymentTargetStatus.APPLYING, 1, null, null, now);
    success.applyStatus(
        "job_1",
        3,
        DeploymentTargetStatus.SUCCEEDED,
        1,
        null,
        mapper.createObjectNode().put("verified", true),
        now);
    deployment.aggregate(List.of(failed, success), now);
    assertEquals(DeploymentStatus.PARTIALLY_SUCCEEDED, deployment.status());
    var retry = Deployment.retry("dep_2", "actor_1", deployment, hash, now);
    var retried = DeploymentTarget.retry("dt_2", retry, failed);
    assertEquals(failed.id(), retried.retryOfDeploymentTargetId());
    assertEquals(0, retried.attempt());
    assertThrows(DaisyException.class, () -> DeploymentTarget.retry("dt_3", retry, success));
    assertThrows(
        DaisyException.class,
        () -> Deployment.rollback("dep_3", "actor_1", deployment, null, hash, now));
  }

  @Test
  void planCannotPersistUnknownSecretFieldsOrHideDeletionActions() {
    var target = target(deployment("dep_1"), "dt_1");
    var valid = plan(target, false);
    var summary = (ObjectNode) valid.summary();
    summary.put("tfstate", "raw");
    assertThrows(
        DaisyException.class,
        () ->
            PlanRevision.create(
                "plan_2",
                target.id(),
                "job_1",
                "prj_1",
                target.targetId(),
                2,
                "instance/job/1",
                "source_2",
                hash,
                "script_1",
                "artifact/plan",
                hash,
                summary,
                mapper.createArrayNode(),
                now,
                now.plusSeconds(600),
                null));
    var resources = mapper.createArrayNode();
    var resource = resources.addObject().put("address", "aws_instance.app");
    resource.putArray("actions").add("delete").add("create");
    assertThrows(
        DaisyException.class,
        () ->
            PlanRevision.create(
                "plan_2",
                target.id(),
                "job_1",
                "prj_1",
                target.targetId(),
                2,
                "instance/job/1",
                "source_2",
                hash,
                "script_1",
                "artifact/plan",
                hash,
                valid.summary(),
                resources,
                now,
                now.plusSeconds(600),
                null));
  }
}
