package com.teamdaisy.server.deployment.application;

import com.fasterxml.jackson.databind.JsonNode;
import java.util.List;

/** The project owner validates ownership, credentials, immutable tags and manifest inputs. */
public interface ExecutionInputs {
  record TargetInput(String id, JsonNode snapshot, String stateIdentity) {}

  record BuildInput(String sourceVersionId, String commitSha, JsonNode imageRefs) {}

  record Captured(
      JsonNode repository, JsonNode commonInput, List<TargetInput> targets, BuildInput source) {}

  record FrozenTarget(
      String deploymentTargetId,
      String targetId,
      JsonNode snapshot,
      String stateIdentity,
      String inputHash,
      String scriptId) {}

  record FrozenInput(
      String deploymentId,
      String projectId,
      String commitSha,
      JsonNode repository,
      JsonNode commonInput,
      BuildInput source,
      List<FrozenTarget> targets) {}

  Captured capture(
      String actorId, String projectId, String commitSha, List<String> targetIds, JsonNode input);

  void verifyFrozen(String actorId, String projectId, FrozenInput input);

  /** Must verify the selected source or exact PREPARE request/run before recording the build. */
  BuildInput recordBuild(DeploymentExecutionService.BuildResult result);
}
