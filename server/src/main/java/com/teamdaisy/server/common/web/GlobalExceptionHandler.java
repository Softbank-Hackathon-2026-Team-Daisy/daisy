package com.teamdaisy.server.common.web;

import com.fasterxml.jackson.databind.PropertyNamingStrategies;
import com.teamdaisy.server.common.error.DaisyException;
import com.teamdaisy.server.common.error.ErrorCode;
import java.util.Map;
import java.util.TreeMap;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.dao.OptimisticLockingFailureException;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpStatusCode;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.HttpRequestMethodNotSupportedException;
import org.springframework.web.bind.MethodArgumentNotValidException;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;
import org.springframework.web.context.request.ServletWebRequest;
import org.springframework.web.context.request.WebRequest;
import org.springframework.web.servlet.mvc.method.annotation.ResponseEntityExceptionHandler;

@RestControllerAdvice
public class GlobalExceptionHandler extends ResponseEntityExceptionHandler {
  private static final Logger LOG = LoggerFactory.getLogger(GlobalExceptionHandler.class);

  @ExceptionHandler(DaisyException.class)
  public ResponseEntity<Object> handleDaisy(DaisyException exception, WebRequest request) {
    ErrorCode code = exception.errorCode();
    return respond(
        exception,
        code,
        exception.details(),
        new HttpHeaders(),
        HttpStatusCode.valueOf(code.status()),
        request);
  }

  @ExceptionHandler(OptimisticLockingFailureException.class)
  public ResponseEntity<Object> handleOptimisticLock(
      OptimisticLockingFailureException exception, WebRequest request) {
    return respond(
        exception,
        ErrorCode.STATE_CONFLICT,
        Map.of(),
        new HttpHeaders(),
        HttpStatusCode.valueOf(409),
        request);
  }

  @ExceptionHandler(Exception.class)
  public ResponseEntity<Object> handleUnexpected(Exception exception, WebRequest request) {
    return respond(
        exception,
        ErrorCode.INTERNAL,
        Map.of(),
        new HttpHeaders(),
        HttpStatusCode.valueOf(500),
        request);
  }

  @Override
  protected ResponseEntity<Object> handleHttpRequestMethodNotSupported(
      HttpRequestMethodNotSupportedException exception,
      HttpHeaders headers,
      HttpStatusCode status,
      WebRequest request) {
    // The framework's default 405 handler logs the raw exception message.
    return handleExceptionInternal(exception, null, headers, status, request);
  }

  @Override
  protected ResponseEntity<Object> handleExceptionInternal(
      Exception exception,
      Object body,
      HttpHeaders headers,
      HttpStatusCode status,
      WebRequest request) {
    ErrorCode code =
        switch (status.value()) {
          case 400, 405, 406, 413, 415 -> ErrorCode.VALIDATION_FAILED;
          case 401 -> ErrorCode.UNAUTHENTICATED;
          case 403 -> ErrorCode.FORBIDDEN;
          case 404 -> ErrorCode.NOT_FOUND;
          case 409 -> ErrorCode.STATE_CONFLICT;
          case 422 -> ErrorCode.MANIFEST_INVALID;
          case 429 -> ErrorCode.RATE_LIMITED;
          default -> ErrorCode.INTERNAL;
        };
    Map<String, Object> details = Map.of();
    if (exception instanceof MethodArgumentNotValidException validation) {
      Map<String, String> fields = new TreeMap<>();
      validation
          .getBindingResult()
          .getFieldErrors()
          .forEach(
              error -> {
                // Only the root property is safe; map keys and array paths may contain submitted
                // values.
                String field = error.getField().split("[.\\[]", 2)[0];
                if (field.matches("[A-Za-z_][A-Za-z0-9_]{0,63}")) {
                  fields.put(
                      PropertyNamingStrategies.SNAKE_CASE.nameForField(null, null, field),
                      "값을 확인해 주세요.");
                }
              });
      if (!fields.isEmpty()) {
        details = Map.of("fields", fields);
      }
    }
    return respond(exception, code, details, headers, status, request);
  }

  private ResponseEntity<Object> respond(
      Exception exception,
      ErrorCode code,
      Map<String, ?> details,
      HttpHeaders headers,
      HttpStatusCode status,
      WebRequest request) {
    if (status.is5xxServerError()) {
      LOG.error("request_failure code={} type={}", code.name(), exception.getClass().getName());
    }
    if (request instanceof ServletWebRequest servlet && servlet.getResponse() != null) {
      var response = servlet.getResponse();
      String contentType = response.getContentType();
      if (response.isCommitted()) {
        return null;
      }
      // An SSE content type alone does not prove streaming started: pre-stream errors need a
      // status.
      if (contentType != null && contentType.startsWith(MediaType.TEXT_EVENT_STREAM_VALUE)) {
        response.setContentType(null);
      }
    }
    HttpHeaders responseHeaders = new HttpHeaders();
    responseHeaders.putAll(headers);
    responseHeaders.setContentType(MediaType.APPLICATION_JSON);
    return new ResponseEntity<>(ErrorResponse.of(code, details), responseHeaders, status);
  }
}
