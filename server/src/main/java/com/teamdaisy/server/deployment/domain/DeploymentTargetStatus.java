package com.teamdaisy.server.deployment.domain;

import jakarta.persistence.AttributeConverter;

public enum DeploymentTargetStatus {
  WAITING("waiting"),
  GENERATING("generating"),
  VALIDATING("validating"),
  AWAITING_APPROVAL("awaiting_approval"),
  APPLYING("applying"),
  VERIFYING("verifying"),
  SUCCEEDED("succeeded"),
  FAILED("failed"),
  CANCELLED("cancelled");

  private final String code;

  DeploymentTargetStatus(String code) {
    this.code = code;
  }

  public String code() { return code; }
  public boolean terminal() { return this == SUCCEEDED || this == FAILED || this == CANCELLED; }
  public boolean running() {
    return this == GENERATING || this == VALIDATING || this == APPLYING || this == VERIFYING;
  }

  @jakarta.persistence.Converter
  public static class Converter implements AttributeConverter<DeploymentTargetStatus, String> {
    @Override
    public String convertToDatabaseColumn(DeploymentTargetStatus value) {
      return value == null ? null : value.code;
    }

    @Override
    public DeploymentTargetStatus convertToEntityAttribute(String code) {
      if (code == null) {
        return null;
      }
      for (DeploymentTargetStatus value : values()) {
        if (value.code.equals(code)) {
          return value;
        }
      }
      throw new IllegalArgumentException("Unknown DeploymentTargetStatus code");
    }
  }
}
