package com.teamdaisy.server.deployment.application;

/** Implemented by the identity/project owner; missing implementations must deny access. */
public interface ExecutionAccess {
  void requireRead(String actorId, String projectId);

  void requireWrite(String actorId, String projectId);
}
