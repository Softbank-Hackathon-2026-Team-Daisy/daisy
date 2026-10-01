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

  /** Omitted target keys have no pointer, not proof that no infrastructure exists. */
  public Map<String, CurrentDeployment> current(
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
    if (ids.isEmpty()) return Map.of();
    var rows =
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
            (rs, row) ->
                new CurrentRow(
                    rs.getString("id"),
                    rs.getString("target_id"),
                    rs.getString("status"),
                    new CurrentDeployment(
                        rs.getString("deployment_id"),
                        rs.getString("source_version_id"),
                        rs.getString("commit_sha"),
                        images(rs.getString("image_refs")),
                        instant(rs, "finished_at"))));
    var result = new LinkedHashMap<String, CurrentDeployment>();
    for (var row : rows) {
      require(Objects.equals(requested.get(row.targetId()), row.id()), ErrorCode.NOT_FOUND);
      require(
          "succeeded".equals(row.status()) && row.value().deployedAt() != null,
          ErrorCode.STATE_CONFLICT);
      result.put(row.targetId(), row.value());
    }
    long expected = requested.values().stream().filter(Objects::nonNull).count();
    require(result.size() == expected, ErrorCode.NOT_FOUND);
    return Collections.unmodifiableMap(result);
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
    var policy = access.getIfAvailable();
    require(policy != null, ErrorCode.FORBIDDEN);
    policy.requireRead(actor, project);
  }

  private List<ServiceImage> images(String value) {
    if (value == null) return null;
    try {
      JsonNode images = mapper.readTree(value);
      require(images.isObject() && !images.isEmpty(), ErrorCode.STATE_CONFLICT);
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

  private record CurrentRow(String id, String targetId, String status, CurrentDeployment value) {}
}
