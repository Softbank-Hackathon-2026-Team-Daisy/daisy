package com.teamdaisy.server.common.web;

import com.teamdaisy.server.common.error.ErrorCode;
import java.util.Map;

public record ErrorResponse(Error error) {
  public static ErrorResponse of(ErrorCode code, Map<String, ?> details) {
    return new ErrorResponse(new Error(code.name(), code.message(), details, code.retryable()));
  }

  public record Error(String code, String message, Map<String, ?> details, boolean retryable) {
    public Error {
      details = details == null ? Map.of() : Map.copyOf(details);
    }
  }
}
