package com.teamdaisy.server.deployment.application;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.teamdaisy.server.common.error.DaisyException;
import com.teamdaisy.server.common.error.ErrorCode;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.time.Instant;
import java.util.*;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.jdbc.core.namedparam.NamedParameterJdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/** Read projections for the project API; never guesses or updates the current target pointer. */
@Service
@Transactional(readOnly = true)
public class DeploymentQueryService {
  public record CurrentPointer(String targetId, String deploymentTargetId) {}

  public record ServiceImage(String service, String imageRef, String imageDigest) {}

  public record CurrentDeployment(
      String deploymentId,
      String sourceVersionId,
      String commitSha,
      List<ServiceImage> images,
      Instant deployedAt) {}

  public record SuccessfulDeployment(String targetId, String deploymentId, Instant deployedAt) {}

  public record CurrentResult(String status, CurrentDeployment deployment) {}

  private final NamedParameterJdbcTemplate jdbc;
  private final ObjectProvider<ExecutionAccess> access;
  private final ObjectMapper mapper;

  public DeploymentQueryService(
      NamedParameterJdbcTemplate jdbc,
      ObjectProvider<ExecutionAccess> access,
      ObjectMapper mapper) {
    this.jdbc = jdbc;
    this.access = access;
    this.mapper = mapper;
  }

  /** Resolves a deployment's project only after read access; commands still check write access. */
  public String projectIdOf(String actorId, String deploymentId) {
    id(actorId);
    id(deploymentId);
    var policy = policy();
    var projects =
        jdbc.queryForList(
            "select project_id from deployment where id=:id",
            Map.of("id", deploymentId),
            String.class);
    require(!projects.isEmpty(), ErrorCode.NOT_FOUND);
    String project = projects.getFirst();
    policy.requireRead(actorId, project);
    return project;
  }

  /** Compatibility query: do not catch its 404/409 for per-target fallback; use currentByTarget. */
  public Map<String, CurrentDeployment> current(
      String actorId, String projectId, List<CurrentPointer> pointers) {
    var result = new LinkedHashMap<String, CurrentDeployment>();
    for (var entry : lookupCurrent(actorId, projectId, pointers).entrySet()) {
      var lookup = entry.getValue();
      if (lookup.failure() != null) throw new DaisyException(lookup.failure());
      if (lookup.deployment() != null) result.put(entry.getKey(), lookup.deployment());
    }
    return Collections.unmodifiableMap(result);
  }

  /** Pointer failures are data; authorization and database failures still reject the request. */
  public Map<String, CurrentResult> currentByTarget(
      String actorId, String projectId, List<CurrentPointer> pointers) {
    var result = new LinkedHashMap<String, CurrentResult>();
    lookupCurrent(actorId, projectId, pointers)
        .forEach(
            (target, lookup) ->
                result.put(
                    target,
                    new CurrentResult(
                        lookup.failure() != null
                            ? "unverified"
                            : lookup.deployment() == null ? "none" : "confirmed",
                        lookup.deployment())));
    return Collections.unmodifiableMap(result);
  }

  private Map<String, CurrentLookup> lookupCurrent(
      String actorId, String projectId, List<CurrentPointer> pointers) {
    authorize(actorId, projectId);
    batch(pointers);
    var requested = new LinkedHashMap<String, String>();
    for (var pointer : pointers) {
      require(pointer != null, ErrorCode.VALIDATION_FAILED);
      id(pointer.targetId());
      require(!requested.containsKey(pointer.targetId()), ErrorCode.VALIDATION_FAILED);
      if (pointer.deploymentTargetId() != null) id(pointer.deploymentTargetId());
      requested.put(pointer.targetId(), pointer.deploymentTargetId());
    }
    var ids = requested.values().stream().filter(Objects::nonNull).distinct().toList();
    var rows = new HashMap<String, CurrentRow>();
    if (!ids.isEmpty())
      jdbc.query(
          """
        select dt.id, dt.target_id, dt.status, dt.finished_at,
               d.id as deployment_id, d.source_version_id, d.commit_sha, d.image_refs::text
        from deployment_target dt
        join deployment d on d.id=dt.deployment_id and d.project_id=dt.project_id
        where dt.project_id=:project and dt.id in (:ids)
        order by dt.target_id
        """,
          Map.of("project", projectId, "ids", ids),
          rs -> {
            var row =
                new CurrentRow(
                    rs.getString("id"),
                    rs.getString("target_id"),
                    rs.getString("status"),
                    rs.getString("deployment_id"),
                    rs.getString("source_version_id"),
                    rs.getString("commit_sha"),
                    rs.getString("image_refs"),
                    instant(rs, "finished_at"));
            rows.put(row.id(), row);
          });
    var result = new LinkedHashMap<String, CurrentLookup>();
    requested.forEach(
        (target, pointer) -> result.put(target, resolve(target, pointer, rows.get(pointer))));
    return result;
  }

  private CurrentLookup resolve(String target, String pointer, CurrentRow row) {
    if (pointer == null) return new CurrentLookup(null, null);
    if (row == null || !target.equals(row.targetId()))
      return new CurrentLookup(null, ErrorCode.NOT_FOUND);
    if (!"succeeded".equals(row.status()) || row.finishedAt() == null)
      return new CurrentLookup(null, ErrorCode.STATE_CONFLICT);
    // Only local image decoding can fail here; never catch access-policy or SQL exceptions.
    try {
      return new CurrentLookup(
          new CurrentDeployment(
              row.deploymentId(),
              row.sourceVersionId(),
              row.commitSha(),
              images(row.images()),
              row.finishedAt()),
          null);
    } catch (DaisyException invalidImages) {
      if (invalidImages.errorCode() != ErrorCode.STATE_CONFLICT) throw invalidImages;
      return new CurrentLookup(null, ErrorCode.STATE_CONFLICT);
    }
  }

  /** Last successful deployment per build and target, not the set of currently serving targets. */
  public Map<String, List<SuccessfulDeployment>> deployedTo(
      String actorId, String projectId, List<String> sourceVersionIds) {
    authorize(actorId, projectId);
    batch(sourceVersionIds);
    var result = new LinkedHashMap<String, List<SuccessfulDeployment>>();
    for (String source : sourceVersionIds) {
      id(source);
      require(!result.containsKey(source), ErrorCode.VALIDATION_FAILED);
      result.put(source, new ArrayList<>());
    }
    if (result.isEmpty()) return Map.of();
    jdbc.query(
        """
        select distinct on (d.source_version_id, dt.target_id)
               d.source_version_id, dt.target_id, d.id as deployment_id, dt.finished_at
        from deployment d
        join deployment_target dt on dt.deployment_id=d.id and dt.project_id=d.project_id
        where d.project_id=:project and d.source_version_id in (:ids)
          and dt.status='succeeded' and dt.finished_at is not null
        order by d.source_version_id, dt.target_id, dt.finished_at desc, d.id desc
        """,
        Map.of("project", projectId, "ids", sourceVersionIds),
        rs -> {
          result
              .get(rs.getString("source_version_id"))
              .add(
                  new SuccessfulDeployment(
                      rs.getString("target_id"),
                      rs.getString("deployment_id"),
                      instant(rs, "finished_at")));
        });
    result.replaceAll((source, values) -> List.copyOf(values));
    return Collections.unmodifiableMap(result);
  }

  private void authorize(String actor, String project) {
    id(actor);
    id(project);
    policy().requireRead(actor, project);
  }

  private ExecutionAccess policy() {
    var policy = access.getIfAvailable();
    require(policy != null, ErrorCode.FORBIDDEN);
    return policy;
  }

  private List<ServiceImage> images(String value) {
    if (value == null) return null;
    try {
      JsonNode images = mapper.readTree(value);
      require(images != null && images.isObject() && !images.isEmpty(), ErrorCode.STATE_CONFLICT);
      var result = new ArrayList<ServiceImage>();
      for (var entry : images.properties()) {
        require(entry.getValue().isObject(), ErrorCode.STATE_CONFLICT);
        result.add(
            new ServiceImage(
                entry.getKey(),
                text(entry.getValue(), "image_ref"),
                text(entry.getValue(), "digest")));
      }
      result.sort(Comparator.comparing(ServiceImage::service));
      return List.copyOf(result);
    } catch (JsonProcessingException exception) {
      throw new DaisyException(ErrorCode.STATE_CONFLICT);
    }
  }

  private static String text(JsonNode node, String key) {
    JsonNode value = node.get(key);
    return value != null && value.isTextual() ? value.asText() : null;
  }

  private static Instant instant(ResultSet rs, String field) throws SQLException {
    var timestamp = rs.getTimestamp(field);
    return timestamp == null ? null : timestamp.toInstant();
  }

  private static void batch(List<?> values) {
    require(values != null && values.size() <= 100, ErrorCode.VALIDATION_FAILED);
  }

  private static void id(String value) {
    require(value != null && !value.isBlank() && value.length() <= 64, ErrorCode.VALIDATION_FAILED);
  }

  private static void require(boolean valid, ErrorCode code) {
    if (!valid) throw new DaisyException(code);
  }

  private record CurrentLookup(CurrentDeployment deployment, ErrorCode failure) {}

  private record CurrentRow(
      String id,
      String targetId,
      String status,
      String deploymentId,
      String sourceVersionId,
      String commitSha,
      String images,
      Instant finishedAt) {}
}
