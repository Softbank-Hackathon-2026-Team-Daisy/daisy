package com.teamdaisy.server.idempotency.application;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.teamdaisy.server.common.error.DaisyException;
import com.teamdaisy.server.common.error.ErrorCode;
import com.teamdaisy.server.common.json.CanonicalJson;
import java.util.Map;
import java.util.function.Supplier;
import org.springframework.jdbc.core.namedparam.MapSqlParameterSource;
import org.springframework.jdbc.core.namedparam.NamedParameterJdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;

@Service
public class IdempotencyService {
  public record Response(int status, JsonNode body) {
    public Response {
      body = CanonicalJson.snapshot(body);
    }

    @Override
    public JsonNode body() {
      return body.deepCopy();
    }
  }

  private final NamedParameterJdbcTemplate jdbc;
  private final CanonicalJson json;
  private final ObjectMapper mapper;

  public IdempotencyService(
      NamedParameterJdbcTemplate jdbc, CanonicalJson json, ObjectMapper mapper) {
    this.jdbc = jdbc;
    this.json = json;
    this.mapper = mapper;
  }

  @Transactional(propagation = Propagation.MANDATORY)
  public Response execute(
      String actor,
      String project,
      String operation,
      String resource,
      String key,
      JsonNode body,
      Supplier<Response> action) {
    for (String value : new String[] {actor, project, operation, resource, key}) {
      if (value == null || value.isBlank() || value.length() > 255)
        throw new DaisyException(ErrorCode.VALIDATION_FAILED);
    }
    if (jdbc.queryForList(
            "select id from project where id=:id and archived_at is null for update",
            Map.of("id", project))
        .isEmpty()) throw new DaisyException(ErrorCode.NOT_FOUND);
    String hash =
        json.hash(
            mapper.valueToTree(
                Map.of(
                    "hash_format_version",
                    1,
                    "actor",
                    actor,
                    "project",
                    project,
                    "operation",
                    operation,
                    "resource",
                    resource,
                    "body",
                    body)));
    var p =
        new MapSqlParameterSource()
            .addValue("actor", actor)
            .addValue("project", project)
            .addValue("operation", operation)
            .addValue("resource", resource)
            .addValue("key", key)
            .addValue("hash", hash);
    var rows =
        jdbc.queryForList(
            "select request_hash,response_status,response_body from idempotency where actor_id=:actor and project_id=:project and operation=:operation and resource_key=:resource and request_key=:key",
            p);
    if (!rows.isEmpty()) {
      var row = rows.getFirst();
      if (!hash.equals(row.get("request_hash"))) throw new DaisyException(ErrorCode.STATE_CONFLICT);
      try {
        return new Response(
            ((Number) row.get("response_status")).intValue(),
            mapper.readTree(row.get("response_body").toString()));
      } catch (com.fasterxml.jackson.core.JsonProcessingException e) {
        throw new DaisyException(ErrorCode.INTERNAL);
      }
    }
    Response response = action.get();
    if (response.status() < 200 || response.status() > 299)
      throw new DaisyException(ErrorCode.INTERNAL);
    p.addValue(
            "deployment",
            response.body().path("deployment_id").isTextual()
                ? response.body().path("deployment_id").asText()
                : null)
        .addValue("status", response.status())
        .addValue("response", json.canonicalize(response.body()));
    jdbc.update(
        "insert into idempotency(actor_id,project_id,operation,resource_key,request_key,request_hash,deployment_id,response_status,response_body,created_at) values(:actor,:project,:operation,:resource,:key,:hash,:deployment,:status,cast(:response as jsonb),now())",
        p);
    return response;
  }
}
