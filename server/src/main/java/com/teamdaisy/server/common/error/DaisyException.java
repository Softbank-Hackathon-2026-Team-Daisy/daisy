package com.teamdaisy.server.common.error;

import java.util.Map;
import java.util.Objects;

public class DaisyException extends RuntimeException {
  private final ErrorCode errorCode;
  private final Map<String, ?> details;

  public DaisyException(ErrorCode errorCode) {
    this(errorCode, Map.of());
  }

  /**
   * Details must contain only safe, explicitly selected response values, never raw input/errors.
   */
  public DaisyException(ErrorCode errorCode, Map<String, ?> details) {
    super(Objects.requireNonNull(errorCode).message());
    this.errorCode = errorCode;
    this.details = details == null ? Map.of() : Map.copyOf(details);
  }

  public ErrorCode errorCode() {
    return errorCode;
  }

  public Map<String, ?> details() {
    return details;
  }
}
