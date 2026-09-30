package com.teamdaisy.server.jenkins.application;

import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.teamdaisy.server.deployment.application.DeploymentExecutionService;
import com.teamdaisy.server.jenkins.application.JenkinsCommandService.CommandScope;
import com.teamdaisy.server.jenkins.infrastructure.JenkinsClient;
import java.util.Map;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.boot.context.event.ApplicationReadyEvent;
import org.springframework.context.event.EventListener;
import org.springframework.scheduling.annotation.EnableScheduling;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

/** One BE process; durable claims commit before any external HTTP. No target state changes here. */
@Component
@EnableScheduling
@ConditionalOnProperty(name = "daisy.jenkins.worker-enabled", havingValue = "true")
public class JenkinsWorker {
  private final JenkinsCommandService commands;
  private final JenkinsClient client;
  private final ObjectMapper mapper;
  private final ObjectProvider<DeploymentExecutionService> deployments;
  private volatile boolean ready;

  public JenkinsWorker(
      JenkinsCommandService commands,
      JenkinsClient client,
      ObjectMapper mapper,
      ObjectProvider<DeploymentExecutionService> deployments) {
    this.commands = commands;
    this.client = client;
    this.mapper = mapper;
    this.deployments = deployments;
  }

  @EventListener(ApplicationReadyEvent.class)
  public void start() {
    if (!client.enabled()) return;
    commands.recoverDispatching();
    ready = true;
  }

  @Scheduled(fixedDelayString = "${daisy.jenkins.worker-delay-ms:1000}")
  public synchronized void tick() {
    if (!ready || !client.enabled()) return;
    CommandScope pending = commands.claimPending();
    if (pending != null) dispatch(pending);
    CommandScope check = commands.claimCheck();
    if (check != null) reconcile(check);
  }

  void dispatch(CommandScope command) {
    if (command.dispatchStatus().equals("rejected")) {
      if (!command.operation().equals("stop"))
        deployments
            .getObject()
            .onCommandRejected(command.id(), commands.rejectionReason(command.id()));
      return;
    }
    try {
      if (command.operation().equals("stop")) {
        CommandScope parent = commands.lookup(command.parentExecutionId());
        if (parent.buildNumber() != null)
          client.stopBuild(parent.jobFullName(), parent.buildNumber());
        else if (parent.queueId() != null) client.cancelQueue(parent.queueId());
        else {
          commands.dispatchFailed(command.id(), false);
          return;
        }
        // A control ACK is not actual parent termination and must not release its locks.
        commands.dispatched(command.id(), parent.queueId(), parent.buildNumber(), "unknown");
      } else {
        var payload =
            mapper.convertValue(command.payload(), new TypeReference<Map<String, Object>>() {});
        var response = client.submit(command.jobFullName(), command.requestId(), payload);
        commands.dispatched(command.id(), response.queueId(), null, "queued");
      }
    } catch (JenkinsClient.RequestException error) {
      commands.dispatchFailed(command.id(), error.definitelyRejected());
      if (error.definitelyRejected() && !command.operation().equals("stop"))
        deployments.getObject().onCommandRejected(command.id(), "confirmed_dispatch_rejected");
    } catch (RuntimeException error) {
      commands.dispatchFailed(command.id(), false);
    }
  }

  void reconcile(CommandScope command) {
    try {
      if (command.dispatchStatus().equals("rejected")) {
        if (!command.operation().equals("stop"))
          deployments
              .getObject()
              .onCommandRejected(command.id(), commands.rejectionReason(command.id()));
        return;
      }
      if (command.operation().equals("stop")) {
        // Lost STOP acknowledgements cannot authorize another control request.
        commands.checkUnconfirmed(command.id(), "lookup_unknown");
        return;
      }
      if (command.dispatchStatus().equals("accepted")
          && command.runStatus().equals("cancelled")
          && command.queueId() != null
          && command.buildNumber() == null) {
        deployments.getObject().onQueueCancelled(command.id());
        return;
      }
      if (command.dispatchStatus().equals("unknown")) {
        var found = client.findRequest(command.jobFullName(), command.requestId());
        if (found.state() == JenkinsClient.LookupState.FOUND)
          commands.dispatched(
              command.id(),
              found.queueId(),
              found.buildNumber(),
              found.buildNumber() == null ? "queued" : "running");
        else
          commands.checkUnconfirmed(
              command.id(),
              found.state() == JenkinsClient.LookupState.AMBIGUOUS
                  ? "lookup_ambiguous"
                  : "lookup_unknown");
      } else if (command.buildNumber() == null && command.queueId() != null) {
        var queue = client.queue(command.jobFullName(), command.queueId());
        if (queue.cancelled()) commands.observed(command.id(), null, "cancelled");
        else
          commands.observed(
              command.id(),
              queue.buildNumber(),
              queue.buildNumber() == null ? "queued" : "running");
      } else if (command.buildNumber() != null) {
        var build = client.build(command.jobFullName(), command.buildNumber());
        String status = runStatus(build);
        if (status == null) commands.checkUnconfirmed(command.id(), "lookup_unconfirmed");
        else commands.observed(command.id(), command.buildNumber(), status);
      } else commands.checkUnconfirmed(command.id(), "lookup_unconfirmed");
    } catch (RuntimeException error) {
      commands.checkUnconfirmed(command.id(), "lookup_unconfirmed");
    }
  }

  static String runStatus(JenkinsClient.BuildSnapshot build) {
    if (build.building()) return "running";
    if (build.result() == null) return null;
    return switch (build.result()) {
      case "SUCCESS" -> "succeeded";
      case "FAILURE", "UNSTABLE" -> "failed";
      case "ABORTED", "NOT_BUILT" -> "cancelled";
      default -> null;
    };
  }
}
