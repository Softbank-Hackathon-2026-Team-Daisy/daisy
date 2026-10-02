package com.teamdaisy.server.deployment.domain;

import jakarta.persistence.AttributeConverter;

public enum DeploymentStatus {
  QUEUED("queued"),
  RUNNING("running"),
  AWAITING_APPROVAL("awaiting_approval"),
  SUCCEEDED("succeeded"),
  PARTIALLY_SUCCEEDED("partially_succeeded"),
  FAILED("failed"),
  CANCELLED("cancelled");

  private final String code;

  DeploymentStatus(String code) {
    this.code = code;
  }

  public String code() {
    return code;
  }

  public boolean terminal() {
    return this == SUCCEEDED || this == PARTIALLY_SUCCEEDED || this == FAILED || this == CANCELLED;
  }

  @jakarta.persistence.Converter
  public static class Converter implements AttributeConverter<DeploymentStatus, String> {
    @Override
    public String convertToDatabaseColumn(DeploymentStatus value) {
      return value == null ? null : value.code;
    }

    @Override
    public DeploymentStatus convertToEntityAttribute(String code) {
      if (code == null) {
        return null;
      }
      for (DeploymentStatus value : values()) {
        if (value.code.equals(code)) {
          return value;
        }
      }
      throw new IllegalArgumentException("Unknown DeploymentStatus code");
    }
  }
}
