package com.teamdaisy.server.jenkins.application;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyMap;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.*;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.teamdaisy.server.deployment.application.DeploymentExecutionService;
import com.teamdaisy.server.jenkins.application.JenkinsCommandService.CommandScope;
import com.teamdaisy.server.jenkins.infrastructure.JenkinsClient;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.ObjectProvider;

class JenkinsWorkerTest {
  private final JenkinsCommandService commands = mock(JenkinsCommandService.class);
  private final JenkinsClient client = mock(JenkinsClient.class);
  private final DeploymentExecutionService deployments = mock(DeploymentExecutionService.class);
  private JenkinsWorker worker;

  @BeforeEach
  @SuppressWarnings("unchecked")
  void setup() {
    ObjectProvider<DeploymentExecutionService> provider = mock(ObjectProvider.class);
    when(provider.getObject()).thenReturn(deployments);
    worker = new JenkinsWorker(commands, client, new ObjectMapper(), provider);
  }

  private CommandScope command(String operation, String dispatch, Long queue, Long build) {
    return new CommandScope(
        "job_1",
        "dep_1",
        "prj_1",
        "request_1",
        operation,
        "stop".equals(operation) ? "job_parent" : null,
        "instance",
        "daisy/" + operation,
        dispatch,
        "unknown",
        queue,
        build,
        new ObjectMapper().createObjectNode());
  }

  @Test
  void disabledWorkerDoesNotClaimOrRecover() {
    worker.start();
    worker.tick();
    verifyNoInteractions(commands);
  }

  @Test
  void claimCommitsThroughServiceBeforeSubmissionAndAcceptedWrite() {
    when(client.enabled()).thenReturn(true);
    when(commands.claimPending()).thenReturn(command("apply", "dispatching", null, null));
    when(client.submit(anyString(), anyString(), anyMap()))
        .thenReturn(new JenkinsClient.Submission(11));
    worker.start();
    worker.tick();
    var order = inOrder(commands, client);
    order.verify(commands).recoverDispatching();
    order.verify(commands).claimPending();
    order.verify(client).submit(eq("daisy/apply"), eq("request_1"), anyMap());
    order.verify(commands).dispatched("job_1", 11L, null, "queued");
    verifyNoInteractions(deployments);
  }

  @Test
  void lostSubmissionRemainsUnknownWithoutResubmitOrTargetFailure() {
    when(client.submit(anyString(), anyString(), anyMap()))
        .thenThrow(new JenkinsClient.RequestException(false));
    worker.dispatch(command("apply", "dispatching", null, null));
    verify(commands).dispatchFailed("job_1", false);
    when(client.findRequest("daisy/apply", "request_1"))
        .thenReturn(new JenkinsClient.RequestLookup(JenkinsClient.LookupState.UNKNOWN, null, null));
    worker.reconcile(command("apply", "unknown", null, null));
    verify(commands).checkUnconfirmed("job_1", "lookup_unknown");
    verify(client, times(1)).submit(anyString(), anyString(), anyMap());
    verifyNoInteractions(deployments);
  }

  @Test
  void definiteRejectionIsPersistedBeforeDomainFailure() {
    when(client.submit(anyString(), anyString(), anyMap()))
        .thenThrow(new JenkinsClient.RequestException(true));
    worker.dispatch(command("apply", "dispatching", null, null));
    var order = inOrder(commands, deployments);
    order.verify(commands).dispatchFailed("job_1", true);
    order.verify(deployments).onCommandRejected("job_1", "confirmed_dispatch_rejected");
  }

  @Test
  void stopAckDoesNotChangeParentTargetOrFinishRun() {
    when(commands.lookup("job_parent")).thenReturn(command("apply", "accepted", 11L, 7L));
    worker.dispatch(command("stop", "dispatching", null, null));
    verify(client).stopBuild("daisy/apply", 7);
    verify(commands).dispatched("job_1", 11L, 7L, "unknown");
    verify(commands, never()).observed(anyString(), any(), anyString());
    verifyNoInteractions(deployments);
  }

  @Test
  void locallyRejectedExpiredApprovalNeverReachesHttp() {
    when(commands.rejectionReason("job_1")).thenReturn("confirmed_not_submitted");
    worker.dispatch(command("apply", "rejected", null, null));
    verify(deployments).onCommandRejected("job_1", "confirmed_not_submitted");
    verifyNoInteractions(client);
  }

  @Test
  void stopDefiniteRejectionDoesNotFailParentTargets() {
    when(commands.lookup("job_parent")).thenReturn(command("apply", "accepted", 11L, 7L));
    doThrow(new JenkinsClient.RequestException(true)).when(client).stopBuild("daisy/apply", 7);
    worker.dispatch(command("stop", "dispatching", null, null));
    verify(commands).dispatchFailed("job_1", true);
    verifyNoInteractions(deployments);
  }

  @Test
  void successUpdatesOnlyJenkinsRunStatus() {
    when(client.build("daisy/apply", 7))
        .thenReturn(new JenkinsClient.BuildSnapshot(false, "SUCCESS"));
    worker.reconcile(command("apply", "accepted", 11L, 7L));
    verify(commands).observed("job_1", 7L, "succeeded");
    verifyNoInteractions(deployments);
    assertThat(JenkinsWorker.runStatus(new JenkinsClient.BuildSnapshot(false, null))).isNull();
  }

  @Test
  void cancelledQueueIsHandedToDurableTargetReconciliation() {
    when(client.queue("daisy/apply", 11)).thenReturn(new JenkinsClient.QueueSnapshot(true, null));
    worker.reconcile(command("apply", "accepted", 11L, null));
    verify(commands).observed("job_1", null, "cancelled");
    verifyNoInteractions(deployments);
    var cancelled =
        new CommandScope(
            "job_1",
            "dep_1",
            "prj_1",
            "request_1",
            "apply",
            null,
            "instance",
            "daisy/apply",
            "accepted",
            "cancelled",
            11L,
            null,
            new ObjectMapper().createObjectNode());
    worker.reconcile(cancelled);
    verify(deployments).onQueueCancelled("job_1");
  }
}
