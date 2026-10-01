package com.teamdaisy.server.jenkins.application;

import com.teamdaisy.server.jenkins.infrastructure.JenkinsClient;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.scheduling.annotation.EnableScheduling;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

@Component
@EnableScheduling
@ConditionalOnProperty(
    name = {"daisy.jenkins.console-enabled", "daisy.jenkins.console-sanitized-utf8-confirmed"},
    havingValue = "true")
public class JenkinsConsoleWorker {
  private final JenkinsConsoleService consoles;
  private final JenkinsClient client;

  public JenkinsConsoleWorker(JenkinsConsoleService consoles, JenkinsClient client) {
    this.consoles = consoles;
    this.client = client;
  }

  @Scheduled(fixedDelayString = "${daisy.jenkins.console-delay-ms:5000}")
  public synchronized void tick() {
    if (!client.enabled()) return;
    int requests = 0;
    for (String candidate : consoles.candidates()) {
      try {
        var owner = consoles.owner(candidate);
        if (owner.complete()) continue;
        if (++requests > 2) break;
        // Exact captured Job/build; client enforces its configured origin and owned Job allowlist.
        var response = client.progressiveLog(owner.job(), owner.build(), owner.cursor());
        consoles.commit(owner, response);
      } catch (RuntimeException error) {
        // Do not log raw response/errors or move the cursor; next bounded poll retries persisted
        // bytes.
        consoles.failed(candidate);
      }
    }
  }
}
