package com.teamdaisy.server.jenkins.api;

import com.teamdaisy.server.jenkins.application.JenkinsCallbackService;
import jakarta.servlet.http.HttpServletRequest;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RestController;

/** Internal service endpoint; the wire protocol remains an infrastructure integration draft. */
@RestController
@ConditionalOnProperty(name = "daisy.jenkins.callbacks-enabled", havingValue = "true")
public class JenkinsCallbackController {
  private final JenkinsCallbackService callbacks;

  public JenkinsCallbackController(JenkinsCallbackService callbacks) {
    this.callbacks = callbacks;
  }

  @PostMapping(path = "/internal/jenkins/callbacks", consumes = "application/json")
  public JenkinsCallbackService.Receipt receive(HttpServletRequest request) {
    var sender = callbacks.authenticate(request);
    var envelope = callbacks.read(request);
    // Spring's service transaction commits before the controller returns the ACK.
    return callbacks.receive(sender, envelope);
  }
}
