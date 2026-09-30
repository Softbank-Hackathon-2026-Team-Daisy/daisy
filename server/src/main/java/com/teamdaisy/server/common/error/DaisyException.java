package com.teamdaisy.server.common.error;

import java.util.Objects;

public class DaisyException extends RuntimeException {
  private final ErrorCode errorCode;

  public DaisyException(ErrorCode errorCode) {
    super(Objects.requireNonNull(errorCode).message());
    this.errorCode = errorCode;
  }

  public ErrorCode errorCode() {
    return errorCode;
  }
}
