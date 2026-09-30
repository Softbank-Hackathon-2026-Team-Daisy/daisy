package com.teamdaisy.server.jenkins.application;

import jakarta.servlet.http.HttpServletRequest;
import java.util.Set;

/** EH supplies service authentication (including credential/certificate checks), never user login. */
public interface ExecutionCallbackAccess {
  VerifiedSender verify(HttpServletRequest request);

  record VerifiedSender(String instanceId, Set<String> permittedJobs) {
    public VerifiedSender {
      permittedJobs = permittedJobs == null ? Set.of() : Set.copyOf(permittedJobs);
    }
  }
}
