package com.teamdaisy.server.deployment.application;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.teamdaisy.server.ai.application.AiUsageService;
import com.teamdaisy.server.common.error.DaisyException;
import com.teamdaisy.server.common.error.ErrorCode;
import com.teamdaisy.server.common.json.CanonicalJson;
import com.teamdaisy.server.deployment.domain.*;
import com.teamdaisy.server.deployment.infrastructure.DeploymentStore;
import com.teamdaisy.server.history.application.EventJournal;
import com.teamdaisy.server.idempotency.application.IdempotencyService;
import com.teamdaisy.server.jenkins.application.JenkinsCommandService;
import com.teamdaisy.server.jenkins.application.JenkinsCommandService.CommandRef;
import com.teamdaisy.server.jenkins.application.JenkinsCommandService.CommandScope;
import com.teamdaisy.server.jenkins.application.JenkinsCommandService.CommandTarget;
import com.teamdaisy.server.script.application.ScriptService;
import java.time.Instant;
import java.util.List;
import java.util.Map;
import java.util.function.Supplier;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.ObjectProvider;

class DeploymentExecutionServiceTest {
  final ObjectMapper mapper=new ObjectMapper().findAndRegisterModules();
  final CanonicalJson json=new CanonicalJson(mapper);
  final DeploymentStore store=mock(DeploymentStore.class);
  final JenkinsCommandService commands=mock(JenkinsCommandService.class);
  final EventJournal journal=mock(EventJournal.class);
  final IdempotencyService idempotency=mock(IdempotencyService.class);
  final ExecutionAccess access=mock(ExecutionAccess.class);
  final ExecutionInputs inputs=mock(ExecutionInputs.class);
  final ObjectProvider<ExecutionAccess> accessProvider=mock(ObjectProvider.class);
  final ObjectProvider<ExecutionInputs> inputProvider=mock(ObjectProvider.class);
  final ScriptService scripts=mock(ScriptService.class);
  final AiUsageService usage=mock(AiUsageService.class);
  final String hash="sha256:"+"a".repeat(64),commit="b".repeat(40);
  final Instant now=Instant.now().minusSeconds(10);
  final DeploymentExecutionService service=new DeploymentExecutionService(store,commands,journal,idempotency,
      accessProvider,inputProvider,scripts,usage,mapper,json);

  @BeforeEach void setup() {
    when(accessProvider.getIfAvailable()).thenReturn(access);
    when(inputProvider.getIfAvailable()).thenReturn(inputs);
    when(idempotency.execute(anyString(),anyString(),anyString(),anyString(),anyString(),any(),any()))
        .thenAnswer(invocation->invocation.<Supplier<IdempotencyService.Response>>getArgument(6).get());
    when(journal.appendDeployment(anyString(),anyString(),any(),anyBoolean()))
        .thenReturn(new EventJournal.AppendResult(1,1,false));
    when(commands.enqueue(anyString(),anyString(),nullable(String.class),anyList(),any()))
        .thenReturn(new CommandRef("job_new","request_new"));
  }
  Deployment deployment() {
    return Deployment.create("dep_1","prj_1","actor_1",commit,mapper.createObjectNode(),
        mapper.createObjectNode().put("hash_format_version",1),hash,now);
  }
  DeploymentTarget target(Deployment deployment) {
    return DeploymentTarget.create("dt_1",deployment,"tgt_1",mapper.createObjectNode().put("name","production"),"state/one");
  }
  PlanRevision plan(DeploymentTarget target,Instant expiry) {
    var summary=mapper.createObjectNode().put("has_delete",true);
    summary.set("counts",mapper.createObjectNode().put("create",0).put("update",0).put("delete",1));summary.putArray("risks");
    var plan=PlanRevision.create("plan_1",target.id(),"job_prepare","prj_1",target.targetId(),1,"instance/job/1","sourceplan_1",hash,"script_1","artifact/plan",hash,summary,mapper.createArrayNode(),now,expiry,null);
    target.bindInput(hash);target.attachExecution("job_prepare");target.adoptPlan(plan,now);
    return plan;
  }
  void stored(Deployment deployment,DeploymentTarget target) {
    when(store.lock("prj_1","dep_1")).thenReturn(deployment);when(store.targets("dep_1")).thenReturn(List.of(target));
  }
  CommandScope scope(String id,String operation,String dispatch,String run) {
    return new CommandScope(id,"dep_1","prj_1","request_1",operation,null,"instance","job",dispatch,run,null,1L,mapper.createObjectNode());
  }
  DeploymentExecutionService.ControlRequest control() {
    return new DeploymentExecutionService.ControlRequest("actor_1","prj_1","dep_1",List.of("tgt_1"),"key");
  }

  @Test void authorizationRunsBeforeIdempotencyAndMissingPolicyFailsClosed() {
    when(accessProvider.getIfAvailable()).thenReturn(null);
    var error=assertThrows(DaisyException.class,()->service.cancel(control()));
    assertEquals(ErrorCode.FORBIDDEN,error.errorCode());verifyNoInteractions(idempotency,store,commands);
  }

  @Test void creationUsesOwnerSnapshotsAndQueuesOneImmutablePrepare() {
    when(inputs.capture(eq("actor_1"),eq("prj_1"),eq(commit),eq(List.of("tgt_1")),any())).thenReturn(
        new ExecutionInputs.Captured(mapper.createObjectNode(),mapper.createObjectNode().put("hash_format_version",1),
            List.of(new ExecutionInputs.TargetInput("tgt_1",mapper.createObjectNode().put("name","production"),"state/one")),null));
    var response=service.create(new DeploymentExecutionService.CreateRequest("actor_1","prj_1",commit,List.of("tgt_1"),mapper.createObjectNode(),"key"));
    assertEquals(201,response.status());verify(access).requireWrite("actor_1","prj_1");
    verify(commands).enqueue(anyString(),eq("prepare"),isNull(),argThat(targets->targets.size()==1 && targets.getFirst().planId()==null),
        argThat(payload->payload.path("commit_sha").asText().equals(commit) && payload.path("allow_ai_autofix").asBoolean()));
  }

  @Test void deletionConfirmationAndExpiryPreventApplyAndValidApprovalQueuesExactPlan() {
    var deployment=deployment();var target=target(deployment);var plan=plan(target,Instant.now().plusSeconds(300));stored(deployment,target);
    var approval=Approval.pending("apv_1",plan,now,plan.expiresAt());when(store.plan("plan_1")).thenReturn(plan);when(store.approval("apv_1")).thenReturn(approval);
    var wrong=new DeploymentExecutionService.DecisionRequest("actor_1","prj_1","dep_1",Map.of("tgt_1",new DeploymentExecutionService.Decision("apv_1",true,"wrong")),"wrongkey");
    assertThrows(DaisyException.class,()->service.decide(wrong));verify(commands,never()).enqueue(anyString(),eq("apply"),any(),any(),any());
    var correct=new DeploymentExecutionService.DecisionRequest("actor_1","prj_1","dep_1",Map.of("tgt_1",new DeploymentExecutionService.Decision("apv_1",true,"production")),"key");
    service.decide(correct);assertEquals("approved",approval.decision());assertEquals("job_new",target.currentExecutionId());
    verify(commands).enqueue(eq("dep_1"),eq("apply"),isNull(),eq(List.of(new CommandTarget("dt_1",hash,"plan_1",hash,"state/one"))),any());
    var expiredTarget=target(deployment());var expiredPlan=plan(expiredTarget,now.plusSeconds(1));
    var expiredApproval=Approval.pending("apv_expired",expiredPlan,now,expiredPlan.expiresAt());
    assertThrows(DaisyException.class,()->expiredApproval.decide(expiredPlan,expiredTarget,"actor_1",true,"production",Instant.now()));
  }

  @Test void pendingCancellationHasEvidenceButStopKeepsCurrentApplyOwner() {
    var deployment=deployment();var target=target(deployment);target.attachExecution("job_prepare");stored(deployment,target);
    when(commands.lookup("job_prepare")).thenReturn(scope("job_prepare","prepare","pending","unknown"));
    when(commands.executionTargets("job_prepare")).thenReturn(List.of(new CommandTarget("dt_1",null,null,null,"state/one")));
    when(commands.cancelPending("job_prepare")).thenReturn(true);
    service.cancel(control());assertEquals(DeploymentTargetStatus.CANCELLED,target.status());
    verify(commands).releaseOwnedLock(eq("job_prepare"),eq("dt_1"),eq("backend"),anyString());
    var applyingDeployment=deployment();var applying=target(applyingDeployment);plan(applying,Instant.now().plusSeconds(300));applying.attachExecution("job_apply");stored(applyingDeployment,applying);
    when(commands.lookup("job_apply")).thenReturn(scope("job_apply","apply","accepted","running"));
    when(commands.executionTargets("job_apply")).thenReturn(List.of(new CommandTarget("dt_1",hash,"plan_1",hash,"state/one")));
    service.cancel(control());assertFalse(applying.status().terminal());assertEquals("job_apply",applying.currentExecutionId());
    verify(commands).enqueue(eq("dep_1"),eq("stop"),eq("job_apply"),any(),any());
  }

  @Test void retryCreatesNewLineageAndNeverModifiesOriginalFailure() {
    var deployment=deployment();var target=target(deployment);target.attachExecution("job_prepare");target.applyStatus("job_prepare",1,DeploymentTargetStatus.FAILED,3,"failed",null,now);deployment.aggregate(List.of(target),now);stored(deployment,target);
    service.retry(control());assertEquals(DeploymentTargetStatus.FAILED,target.status());
    verify(store).save(argThat(value->value instanceof Deployment next && next.kind().equals("retry") && next.retryOfDeploymentId().equals("dep_1")));
    verify(store).save(argThat(value->value instanceof DeploymentTarget next && next.retryOfDeploymentTargetId().equals("dt_1") && next.attempt()==0));
    verify(inputs).verifyFrozen(eq("actor_1"),eq("prj_1"),any());
  }

  @Test void rollbackUsesSuccessfulOriginalAndDisablesAutomaticFixes() {
    var deployment=deployment();var target=target(deployment);plan(target,Instant.now().plusSeconds(300));
    var images=mapper.createObjectNode();images.set("app",mapper.createObjectNode().put("commit_sha",commit).put("image_ref","registry/app:"+commit));deployment.bindSource("src_1",commit,images,hash);
    target.applyStatus("job_prepare",1,DeploymentTargetStatus.SUCCEEDED,1,null,mapper.createObjectNode().put("plan_id","plan_1"),now);deployment.aggregate(List.of(target),now);stored(deployment,target);
    service.rollback(new DeploymentExecutionService.RollbackRequest("actor_1","prj_1","dep_1",null,"key"));
    verify(store).save(argThat(value->value instanceof Deployment next && next.rollbackOfDeploymentId().equals("dep_1")));
    verify(commands).enqueue(anyString(),eq("prepare"),isNull(),anyList(),argThat(payload->!payload.path("allow_ai_autofix").asBoolean() && payload.path("restore_scripts").size()==1));
  }

  @Test void exactStateReplayIsStableAfterTargetCompletesAndCannotAdvanceAgain() {
    var deployment=deployment();var target=target(deployment);plan(target,Instant.now().plusSeconds(300));
    var images=mapper.createObjectNode();images.set("app",mapper.createObjectNode().put("commit_sha",commit).put("image_ref","registry/app:"+commit));deployment.bindSource("src_1",commit,images,hash);
    target.attachExecution("job_apply");stored(deployment,target);
    when(store.plan("plan_1")).thenReturn(plan(target,Instant.now().plusSeconds(300)));
    target.attachExecution("job_apply");
    var scope=scope("job_apply","apply","accepted","running");
    when(commands.requireScope("job_apply","dep_1","dt_1")).thenReturn(scope);
    when(commands.executionTargets("job_apply")).thenReturn(List.of(new CommandTarget("dt_1",hash,"plan_1",hash,"state/one")));
    var result=mapper.createObjectNode().put("plan_id","plan_1").put("plan_digest",hash).put("input_hash",hash);result.set("image_refs",images);
    var receipt=new DeploymentExecutionService.StateResult("prj_1","dep_1","job_apply","dt_1","instance/job/1","event_1",1,DeploymentTargetStatus.SUCCEEDED,1,null,result,now);
    java.util.List<com.teamdaisy.server.history.application.DeploymentEvent> callbacks=new java.util.ArrayList<>();
    when(journal.appendDeployment(anyString(),anyString(),any(),anyBoolean())).thenAnswer(invocation->{
      var event=invocation.<com.teamdaisy.server.history.application.DeploymentEvent>getArgument(2);
      if(event.sourceEventId().equals("event_1")) {
        callbacks.add(event);return new EventJournal.AppendResult(1,1,callbacks.size()>1);
      }
      return new EventJournal.AppendResult(2,2,false);
    });
    service.acceptState(receipt);service.acceptState(receipt);
    assertEquals(DeploymentTargetStatus.SUCCEEDED,target.status());assertEquals(callbacks.get(0).payload(),callbacks.get(1).payload());
    verify(commands,times(1)).recordTargetState(eq("job_apply"),eq("dt_1"),eq("succeeded"),eq(1L),any(),eq(true));
    verify(commands,times(1)).releaseOwnedLock("job_apply","dt_1","instance/job/1","event_1");
  }

  @Test void planArrivingBeforeProgressStillCarriesAttemptAndOlderProgressIsIgnored() {
    var deployment=deployment();var target=target(deployment);target.bindInput(hash);target.attachExecution("job_prepare");stored(deployment,target);
    var images=mapper.createObjectNode();images.set("app",mapper.createObjectNode().put("commit_sha",commit).put("image_ref","registry/app:"+commit));deployment.bindSource("src_1",commit,images,hash);
    when(commands.requireScope("job_prepare","dep_1","dt_1")).thenReturn(scope("job_prepare","prepare","accepted","running"));when(store.nextRevision("dt_1")).thenReturn(1);
    var summary=mapper.createObjectNode().put("has_delete",false);summary.set("counts",mapper.createObjectNode().put("create",1).put("update",0).put("delete",0));summary.putArray("risks");
    service.acceptPlan(new DeploymentExecutionService.PlanResult("prj_1","dep_1","job_prepare","dt_1","instance/job/1","event_plan",5,"source_plan",hash,"script_1",false,2,"artifact/plan",hash,summary,mapper.createArrayNode(),Instant.now().plusSeconds(300),null,now));
    assertEquals(2,target.attempt());assertEquals(DeploymentTargetStatus.AWAITING_APPROVAL,target.status());
    service.acceptState(new DeploymentExecutionService.StateResult("prj_1","dep_1","job_prepare","dt_1","instance/job/1","event_old",1,DeploymentTargetStatus.GENERATING,1,null,null,now));
    assertEquals(2,target.attempt());assertEquals(DeploymentTargetStatus.AWAITING_APPROVAL,target.status());
    verify(commands,never()).recordTargetState(anyString(),anyString(),anyString(),anyLong(),any(),anyBoolean());
  }
}
