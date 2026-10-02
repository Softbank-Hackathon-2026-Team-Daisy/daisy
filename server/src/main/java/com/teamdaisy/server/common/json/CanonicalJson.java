package com.teamdaisy.server.common.json;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.SerializationFeature;
import com.fasterxml.jackson.databind.node.ArrayNode;
import com.fasterxml.jackson.databind.node.JsonNodeFactory;
import com.fasterxml.jackson.databind.node.ObjectNode;
import com.teamdaisy.server.common.error.DaisyException;
import com.teamdaisy.server.common.error.ErrorCode;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.HexFormat;
import java.util.TreeMap;
import org.springframework.stereotype.Component;

@Component
public class CanonicalJson {
  public static final int MAX_BYTES = 256 * 1024;
  private final ObjectMapper mapper;

  public CanonicalJson(ObjectMapper mapper) {
    this.mapper = mapper;
  }

  public String canonicalize(JsonNode value) {
    try {
      String encoded =
          mapper
              .writer()
              .without(SerializationFeature.INDENT_OUTPUT)
              .writeValueAsString(sorted(value, 0));
      if (encoded.getBytes(StandardCharsets.UTF_8).length > MAX_BYTES) invalid();
      return encoded;
    } catch (JsonProcessingException e) {
      throw new DaisyException(ErrorCode.VALIDATION_FAILED);
    }
  }

  public String hash(JsonNode value) {
    try {
      return "sha256:"
          + HexFormat.of()
              .formatHex(
                  MessageDigest.getInstance("SHA-256")
                      .digest(canonicalize(value).getBytes(StandardCharsets.UTF_8)));
    } catch (NoSuchAlgorithmException e) {
      throw new IllegalStateException(e);
    }
  }

  public JsonNode copy(JsonNode value) {
    return snapshot(value);
  }

  public static JsonNode snapshot(JsonNode value) {
    JsonNode copy = sorted(value, 0);
    if (copy.toString().getBytes(StandardCharsets.UTF_8).length > MAX_BYTES) invalid();
    return copy;
  }

  private static JsonNode sorted(JsonNode value, int depth) {
    if (value == null || depth > 100) invalid();
    if (value.isObject()) {
      ObjectNode result = JsonNodeFactory.instance.objectNode();
      var fields = new TreeMap<String, JsonNode>();
      value.fields().forEachRemaining(field -> fields.put(field.getKey(), field.getValue()));
      fields.forEach((key, child) -> result.set(key, sorted(child, depth + 1)));
      return result;
    }
    if (value.isArray()) {
      ArrayNode result = JsonNodeFactory.instance.arrayNode();
      value.forEach(child -> result.add(sorted(child, depth + 1)));
      return result;
    }
    if (!(value.isNull() || value.isTextual() || value.isBoolean() || value.isNumber())
        || ((value.isDouble() || value.isFloat()) && !Double.isFinite(value.doubleValue())))
      invalid();
    return value.deepCopy();
  }

  private static void invalid() {
    throw new DaisyException(ErrorCode.VALIDATION_FAILED);
  }
}
