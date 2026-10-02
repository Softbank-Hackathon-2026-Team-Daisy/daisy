package com.teamdaisy.server.idempotency.domain;

import com.fasterxml.jackson.databind.JsonNode;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import jakarta.persistence.UniqueConstraint;
import java.time.Instant;
import org.hibernate.annotations.JdbcTypeCode;
import org.hibernate.type.SqlTypes;

@Entity
@Table(
    name = "idempotency",
    uniqueConstraints = {
      @UniqueConstraint(
          columnNames = {"actor_id", "project_id", "operation", "resource_key", "request_key"})
    })
public class Idempotency {
  @Id
  @GeneratedValue(strategy = GenerationType.IDENTITY)
  @Column(name = "id", nullable = false)
  private Long id;

  @Column(name = "actor_id", nullable = false, length = 64)
  private String actorId;

  @Column(name = "project_id", nullable = false, length = 64)
  private String projectId;

  @Column(name = "operation", nullable = false, length = 64)
  private String operation;

  @Column(name = "resource_key", nullable = false, length = 255)
  private String resourceKey;

  @Column(name = "request_key", nullable = false, length = 255)
  private String requestKey;

  @Column(name = "request_hash", nullable = false, length = 128)
  private String requestHash;

  @Column(name = "deployment_id", nullable = true, length = 64)
  private String deploymentId;

  @Column(name = "response_status", nullable = false)
  private short responseStatus;

  @JdbcTypeCode(SqlTypes.JSON)
  @Column(name = "response_body", nullable = false, columnDefinition = "jsonb")
  private JsonNode responseBody;

  @Column(name = "created_at", nullable = false, columnDefinition = "timestamptz")
  private Instant createdAt;

  protected Idempotency() {}
}
