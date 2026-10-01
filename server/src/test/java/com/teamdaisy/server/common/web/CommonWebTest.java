package com.teamdaisy.server.common.web;

import static org.hamcrest.Matchers.containsString;
import static org.hamcrest.Matchers.not;
import static org.junit.jupiter.api.Assertions.*;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.*;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

import ch.qos.logback.classic.Logger;
import ch.qos.logback.classic.LoggerContext;
import ch.qos.logback.classic.spi.ILoggingEvent;
import ch.qos.logback.core.read.ListAppender;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.teamdaisy.server.common.error.DaisyException;
import com.teamdaisy.server.common.error.ErrorCode;
import jakarta.servlet.http.HttpServletResponse;
import jakarta.validation.Valid;
import jakarta.validation.constraints.Pattern;
import java.nio.charset.StandardCharsets;
import java.time.Instant;
import java.util.HashMap;
import java.util.Map;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.logging.logback.StructuredLogEncoder;
import org.springframework.boot.test.autoconfigure.json.JsonTest;
import org.springframework.core.env.Environment;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.http.MediaType;
import org.springframework.http.converter.json.MappingJackson2HttpMessageConverter;
import org.springframework.mock.env.MockEnvironment;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.mock.web.MockHttpServletResponse;
import org.springframework.orm.ObjectOptimisticLockingFailureException;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.context.request.ServletWebRequest;

@JsonTest
class CommonWebTest {
  private static final String SECRET = "api-token-secret-example";
  private MockMvc mvc;
  @Autowired private ObjectMapper objectMapper;

  @BeforeEach
  void setup() {
    mvc =
        MockMvcBuilders.standaloneSetup(new TestController())
            .setControllerAdvice(new GlobalExceptionHandler())
            .setMessageConverters(new MappingJackson2HttpMessageConverter(objectMapper))
            .addFilters(new RequestIdFilter())
            .build();
  }

  @Test
  void safeDetailsAndPersistenceFailuresUseDistinctResponses() throws Exception {
    var details = new HashMap<String, Object>();
    details.put("deployment_id", "dep_busy");
    var exception = new DaisyException(ErrorCode.TARGET_LOCKED, details);
    details.put("deployment_id", "changed");
    assertEquals("dep_busy", exception.details().get("deployment_id"));
    assertThrows(UnsupportedOperationException.class, () -> exception.details().clear());
    assertTrue(new DaisyException(ErrorCode.MANIFEST_INVALID, null).details().isEmpty());
    mvc.perform(get("/details"))
        .andExpect(status().isUnprocessableEntity())
        .andExpect(jsonPath("$.error.details.fields.port").value("포트를 확인해 주세요."));
    mvc.perform(get("/persistence/optimistic"))
        .andExpect(status().isConflict())
        .andExpect(jsonPath("$.error.code").value("STATE_CONFLICT"))
        .andExpect(content().string(not(containsString(SECRET))));
    mvc.perform(get("/persistence/integrity"))
        .andExpect(status().isInternalServerError())
        .andExpect(jsonPath("$.error.code").value("INTERNAL"))
        .andExpect(content().string(not(containsString(SECRET))));
  }

  @Test
  void applicationJacksonSettingsSerializeSnakeCaseAndUtcInstant() throws Exception {
    mvc.perform(get("/serialized"))
        .andExpect(status().isOk())
        .andExpect(jsonPath("$.commit_sha").value("abc"))
        .andExpect(jsonPath("$.created_at").value("2026-10-01T00:00:00Z"))
        .andExpect(jsonPath("$.commitSha").doesNotExist());
  }

  @Test
  void everyDomainCodeUsesItsContractStatusAndSafeEnvelope() throws Exception {
    var codes = ErrorCode.values();
    int[] statuses = {400, 401, 403, 404, 409, 409, 422, 429, 500};
    assertEquals(statuses.length, codes.length);
    for (int i = 0; i < codes.length; i++) {
      mvc.perform(get("/failure/" + codes[i].name()).header(RequestIdFilter.HEADER, "req.1_-"))
          .andExpect(status().is(statuses[i]))
          .andExpect(header().string(RequestIdFilter.HEADER, "req.1_-"))
          .andExpect(jsonPath("$.error.code").value(codes[i].name()))
          .andExpect(jsonPath("$.error.message").isString())
          .andExpect(jsonPath("$.error.details").isEmpty())
          .andExpect(jsonPath("$.error.retryable").value(codes[i] == ErrorCode.RATE_LIMITED));
    }
    mvc.perform(get("/param").param("count", "1"))
        .andExpect(status().isOk())
        .andExpect(jsonPath("$.count").value(1))
        .andExpect(jsonPath("$.error").doesNotExist());
    assertTrue(ErrorResponse.of(ErrorCode.INTERNAL, null).error().details().isEmpty());
  }

  @Test
  void validationAndParsingNeverReturnValuesOrConstraintMessages() throws Exception {
    mvc.perform(
            post("/input")
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"account_name\":\"" + SECRET + "\"}"))
        .andExpect(status().isBadRequest())
        .andExpect(jsonPath("$.error.code").value("VALIDATION_FAILED"))
        .andExpect(jsonPath("$.error.details.fields.account_name").value("값을 확인해 주세요."))
        .andExpect(content().string(not(containsString(SECRET))));
    mvc.perform(
            post("/input")
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"value\":\"" + SECRET))
        .andExpect(status().isBadRequest())
        .andExpect(jsonPath("$.error.details").isEmpty())
        .andExpect(content().string(not(containsString(SECRET))));
    for (var request :
        new org.springframework.test.web.servlet.request.MockHttpServletRequestBuilder[] {
          get("/param"), get("/param").param("count", SECRET)
        }) {
      mvc.perform(request)
          .andExpect(status().isBadRequest())
          .andExpect(jsonPath("$.error.code").value("VALIDATION_FAILED"))
          .andExpect(content().string(not(containsString(SECRET))));
    }
  }

  @Test
  void frameworkStatusAndHeadersRemainIntact() throws Exception {
    mvc.perform(get("/missing"))
        .andExpect(status().isNotFound())
        .andExpect(jsonPath("$.error.code").value("NOT_FOUND"));
    mvc.perform(post("/param"))
        .andExpect(status().isMethodNotAllowed())
        .andExpect(header().string("Allow", containsString("GET")))
        .andExpect(jsonPath("$.error.code").value("VALIDATION_FAILED"));
    mvc.perform(post("/input").contentType(MediaType.TEXT_PLAIN).content(SECRET))
        .andExpect(status().isUnsupportedMediaType())
        .andExpect(header().string("Accept", containsString("application/json")))
        .andExpect(content().string(not(containsString(SECRET))));
    mvc.perform(get("/param").param("count", "1").accept(MediaType.IMAGE_PNG))
        .andExpect(status().isNotAcceptable())
        .andExpect(jsonPath("$.error.code").value("VALIDATION_FAILED"));
    mvc.perform(get("/failure/FORBIDDEN").accept(MediaType.TEXT_PLAIN))
        .andExpect(status().isForbidden())
        .andExpect(content().contentTypeCompatibleWith(MediaType.APPLICATION_JSON))
        .andExpect(jsonPath("$.error.code").value("FORBIDDEN"));
  }

  @Test
  void unexpectedFailureIsSanitizedInResponseAndNativeJsonLog() throws Exception {
    Logger logger = (Logger) LoggerFactory.getLogger(GlobalExceptionHandler.class);
    var appender =
        new ListAppender<ILoggingEvent>() {
          @Override
          protected void append(ILoggingEvent event) {
            event.prepareForDeferredProcessing();
            super.append(event);
          }
        };
    appender.setContext(logger.getLoggerContext());
    appender.start();
    logger.addAppender(appender);
    var encoder = new StructuredLogEncoder();
    var encoderContext = new LoggerContext();
    encoderContext.putObject(Environment.class.getName(), new MockEnvironment());
    encoder.setContext(encoderContext);
    encoder.setFormat("logstash");
    try {
      encoder.start();
      mvc.perform(get("/internal").header(RequestIdFilter.HEADER, "safe-trace"))
          .andExpect(status().isInternalServerError())
          .andExpect(jsonPath("$.error.code").value("INTERNAL"))
          .andExpect(jsonPath("$.error.retryable").value(false))
          .andExpect(content().string(not(containsString(SECRET))));
      assertEquals(1, appender.list.size());
      var event = appender.list.getFirst();
      assertNull(event.getThrowableProxy());
      assertEquals("safe-trace", event.getMDCPropertyMap().get("request_id"));
      String json = new String(encoder.encode(event), StandardCharsets.UTF_8);
      var log = new ObjectMapper().readTree(json);
      assertEquals("safe-trace", log.path("request_id").asText());
      assertTrue(log.path("message").asText().contains("java.lang.IllegalStateException"));
      assertFalse(json.contains(SECRET));
      assertFalse(json.contains("SELECT"));
      assertFalse(log.has("stack_trace"));
    } finally {
      encoder.stop();
      encoderContext.stop();
      logger.detachAppender(appender);
      appender.stop();
    }
  }

  @Test
  void preStreamErrorsGetStatusButCommittedStreamsAreNotOverwritten() throws Exception {
    mvc.perform(get("/pre-stream"))
        .andExpect(status().isForbidden())
        .andExpect(content().contentTypeCompatibleWith(MediaType.APPLICATION_JSON))
        .andExpect(jsonPath("$.error.code").value("FORBIDDEN"));
    var response = new MockHttpServletResponse();
    response.setContentType(MediaType.TEXT_EVENT_STREAM_VALUE);
    response.getWriter().write("data: started\n\n");
    response.flushBuffer();
    assertNull(
        new GlobalExceptionHandler()
            .handleUnexpected(
                new IllegalStateException(SECRET),
                new ServletWebRequest(new MockHttpServletRequest(), response)));
    assertEquals(200, response.getStatus());
    assertEquals("data: started\n\n", response.getContentAsString());
    assertEquals(MediaType.TEXT_EVENT_STREAM_VALUE, response.getContentType());
  }

  // MOCK: routes exist only to exercise common MVC infrastructure without a database or business
  // API.
  @RestController
  static class TestController {
    @GetMapping("/details")
    void details() {
      throw new DaisyException(
          ErrorCode.MANIFEST_INVALID, Map.of("fields", Map.of("port", "포트를 확인해 주세요.")));
    }

    @GetMapping("/persistence/{type}")
    void persistence(@PathVariable("type") String type) {
      if (type.equals("optimistic")) {
        throw new ObjectOptimisticLockingFailureException("Deployment", SECRET);
      }
      throw new DataIntegrityViolationException("SELECT password FROM account " + SECRET);
    }

    @GetMapping("/serialized")
    Serialized serialized() {
      return new Serialized("abc", Instant.parse("2026-10-01T00:00:00Z"));
    }

    @GetMapping("/failure/{code}")
    void failure(@PathVariable("code") ErrorCode code) {
      throw new DaisyException(code);
    }

    @GetMapping(value = "/param", produces = MediaType.APPLICATION_JSON_VALUE)
    Map<String, Integer> parameter(@RequestParam("count") int count) {
      return Map.of("count", count);
    }

    @PostMapping(value = "/input", consumes = MediaType.APPLICATION_JSON_VALUE)
    Map<String, Boolean> input(@Valid @RequestBody Input input) {
      return Map.of("ok", true);
    }

    @GetMapping("/internal")
    void internal() {
      throw new IllegalStateException("SELECT password FROM account token=" + SECRET);
    }

    @GetMapping("/pre-stream")
    void preStream(HttpServletResponse response) {
      response.setContentType(MediaType.TEXT_EVENT_STREAM_VALUE);
      throw new DaisyException(ErrorCode.FORBIDDEN);
    }
  }

  record Input(@Pattern(regexp = "valid", message = SECRET) String accountName) {}

  record Serialized(String commitSha, Instant createdAt) {}
}
