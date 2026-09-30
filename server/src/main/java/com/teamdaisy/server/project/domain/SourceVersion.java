package com.teamdaisy.server.project.domain;

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
    name = "source_version",
    uniqueConstraints = {
      @UniqueConstraint(columnNames = {"id", "project_id"}),
      @UniqueConstraint(columnNames = {"source", "external_build_id"})
    })
public class SourceVersion {
  @Id
  @Column(name = "id", nullable = false, length = 64)
  private String id;

  @Column(name = "project_id", nullable = false, length = 64)
  private String projectId;

  @Column(name = "source", nullable = false, length = 255)
  private String source;

  @Column(name = "external_build_id", nullable = false, length = 255)
  private String externalBuildId;

  @Column(name = "commit_sha", nullable = false, length = 64)
  private String commitSha;

  @Column(name = "branch", nullable = true, length = 255)
  private String branch;

  @Column(name = "status", nullable = false, length = 32)
  private String status;

  @JdbcTypeCode(SqlTypes.JSON)
  @Column(name = "image_refs", nullable = true, columnDefinition = "jsonb")
  private JsonNode imageRefs;

  @JdbcTypeCode(SqlTypes.JSON)
  @Column(name = "manifest_snapshot", nullable = true, columnDefinition = "jsonb")
  private JsonNode manifestSnapshot;

  @Column(name = "manifest_ref", nullable = true, columnDefinition = "text")
  private String manifestRef;

  @Column(name = "manifest_digest", nullable = true, length = 128)
  private String manifestDigest;

  @Column(name = "manifest_schema_version", nullable = true, length = 64)
  private String manifestSchemaVersion;

  @Column(name = "run_url", nullable = true, columnDefinition = "text")
  private String runUrl;

  @Column(name = "started_at", nullable = true, columnDefinition = "timestamptz")
  private Instant startedAt;

  @Column(name = "finished_at", nullable = true, columnDefinition = "timestamptz")
  private Instant finishedAt;

  @Column(name = "error_summary", nullable = true, columnDefinition = "text")
  private String errorSummary;

  @Column(name = "received_at", nullable = false, columnDefinition = "timestamptz")
  private Instant receivedAt;

  protected SourceVersion() {}
}
