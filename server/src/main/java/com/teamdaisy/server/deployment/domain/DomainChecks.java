package com.teamdaisy.server.deployment.domain;

import com.fasterxml.jackson.databind.JsonNode;
import com.teamdaisy.server.common.error.DaisyException;
import com.teamdaisy.server.common.error.ErrorCode;
import com.teamdaisy.server.common.json.CanonicalJson;
import java.time.Instant;

final class DomainChecks {
  private DomainChecks() {}

  static String text(String value, int max) {
    if (value == null || value.isBlank() || value.length() > max) invalid();
    return value;
  }

  static String id(String value) {
    return text(value, 64);
  }

  static String safeText(String value, int max) {
    text(value, max);
    if (java.util.regex.Pattern.compile(
            "(?i)(-----BEGIN [A-Z ]*PRIVATE KEY|bearer\\s+\\S+|(?:password|secret|token|authorization|credential|access[_-]?key)\\s*[:=]\\s*\\S+|AKIA[A-Z0-9]{16}|gh[pousr]_[A-Za-z0-9]{20,})")
        .matcher(value)
        .find()) invalid();
    return value;
  }

  static void keys(JsonNode value, java.util.Set<String> allowed) {
    if (!value.isObject()) invalid();
    value
        .fieldNames()
        .forEachRemaining(
            key -> {
              if (!allowed.contains(key)) invalid();
            });
  }

  static String hash(String value) {
    if (value == null || !value.matches("sha256:[0-9a-f]{64}")) invalid();
    return value;
  }

  static Instant time(Instant value) {
    if (value == null) invalid();
    return value;
  }

  static JsonNode object(JsonNode value) {
    if (value == null || !value.isObject()) invalid();
    return CanonicalJson.snapshot(value);
  }

  static void require(boolean condition) {
    if (!condition) conflict();
  }

  static void invalid() {
    throw new DaisyException(ErrorCode.VALIDATION_FAILED);
  }

  static void conflict() {
    throw new DaisyException(ErrorCode.STATE_CONFLICT);
  }
}
