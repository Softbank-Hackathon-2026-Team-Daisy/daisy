package com.teamdaisy.server.script.domain;

import com.fasterxml.jackson.databind.JsonNode;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import jakarta.persistence.UniqueConstraint;
import java.time.Instant;
import org.hibernate.annotations.JdbcTypeCode;
import org.hibernate.type.SqlTypes;

@Entity
@Table(
    name = "script",
    uniqueConstraints = {
      @UniqueConstraint(columnNames = {"id", "project_id", "target_id"}),
      @UniqueConstraint(columnNames = {"project_id", "target_id", "version"}),
      @UniqueConstraint(columnNames = {"source", "external_script_id"})
    })
public class Script {
  @Id
  @Column(name = "id", nullable = false, length = 64)
  private String id;

  @Column(name = "project_id", nullable = false, length = 64)
  private String projectId;

  @Column(name = "target_id", nullable = false, length = 64)
  private String targetId;

  @Column(name = "version", nullable = false)
  private int version;

  @Column(name = "source", nullable = false, length = 512)
  private String source;

  @Column(name = "external_script_id", nullable = false, length = 255)
  private String externalScriptId;

  @Column(name = "source_deployment_target_id", nullable = false, length = 64)
  private String sourceDeploymentTargetId;

  @Column(name = "artifact_ref", nullable = false, columnDefinition = "text")
  private String artifactRef;

  @Column(name = "content_digest", nullable = false, length = 128)
  private String contentDigest;

  @Column(name = "compatibility_key", nullable = true, length = 255)
  private String compatibilityKey;

  @JdbcTypeCode(SqlTypes.JSON)
  @Column(name = "metadata", nullable = true, columnDefinition = "jsonb")
  private JsonNode metadata;

  @Column(name = "validated_at", nullable = false, columnDefinition = "timestamptz")
  private Instant validatedAt;

  @Column(name = "received_at", nullable = false, columnDefinition = "timestamptz")
  private Instant receivedAt;

  @Column(name = "artifact_expires_at", nullable = true, columnDefinition = "timestamptz")
  private Instant artifactExpiresAt;

  @Column(name = "unavailable_at", nullable = true, columnDefinition = "timestamptz")
  private Instant unavailableAt;

  protected Script() {}
}
