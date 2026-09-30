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
  static String id(String value) { return text(value, 64); }
  static String hash(String value) {
    if (value == null || !value.matches("sha256:[0-9a-f]{64}")) invalid();
    return value;
  }
  static Instant time(Instant value) { if (value == null) invalid(); return value; }
  static JsonNode object(JsonNode value) {
    if (value == null || !value.isObject()) invalid();
    return CanonicalJson.snapshot(value);
  }
  static void require(boolean condition) { if (!condition) conflict(); }
  static void invalid() { throw new DaisyException(ErrorCode.VALIDATION_FAILED); }
  static void conflict() { throw new DaisyException(ErrorCode.STATE_CONFLICT); }
}
