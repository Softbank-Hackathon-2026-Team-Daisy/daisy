package com.teamdaisy.server.identity.domain;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import jakarta.persistence.UniqueConstraint;
import java.time.Instant;

@Entity
@Table(
    name = "account",
    uniqueConstraints = {@UniqueConstraint(columnNames = {"username"})})
public class Account {
  @Id
  @Column(name = "id", nullable = false, length = 64)
  private String id;

  @Column(name = "username", nullable = false, length = 128)
  private String username;

  @Column(name = "password_hash", nullable = false, columnDefinition = "text")
  private String passwordHash;

  @Column(name = "display_name", nullable = false, length = 128)
  private String displayName;

  @Column(name = "role", nullable = false, length = 32)
  private String role;

  @Column(name = "created_at", nullable = false, columnDefinition = "timestamptz")
  private Instant createdAt;

  @Column(name = "updated_at", nullable = false, columnDefinition = "timestamptz")
  private Instant updatedAt;

  @Column(name = "disabled_at", nullable = true, columnDefinition = "timestamptz")
  private Instant disabledAt;

  protected Account() {}
}
