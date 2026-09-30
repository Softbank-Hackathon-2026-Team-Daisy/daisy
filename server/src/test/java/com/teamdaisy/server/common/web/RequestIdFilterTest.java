package com.teamdaisy.server.common.web;

import static org.junit.jupiter.api.Assertions.*;

import jakarta.servlet.DispatcherType;
import jakarta.servlet.ServletException;
import java.util.List;
import java.util.UUID;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Test;
import org.slf4j.MDC;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.mock.web.MockHttpServletResponse;

class RequestIdFilterTest {
  private final RequestIdFilter filter = new RequestIdFilter();

  @AfterEach
  void cleanup() {
    MDC.remove("request_id");
  }

  @Test
  void acceptsOnlyOneBoundedAsciiIdAndReturnsTheSameIdInAllScopes() throws Exception {
    for (String valid : List.of("Req.123_-", "a", "a".repeat(64))) {
      var request = new MockHttpServletRequest();
      request.addHeader(RequestIdFilter.HEADER, valid);
      var response = new MockHttpServletResponse();
      filter.doFilter(
          request,
          response,
          (req, res) -> {
            assertEquals(valid, req.getAttribute(RequestIdFilter.ATTRIBUTE));
            assertEquals(valid, MDC.get("request_id"));
          });
      assertEquals(valid, response.getHeader(RequestIdFilter.HEADER));
      assertNull(MDC.get("request_id"));
    }
    for (List<String> invalid :
        List.of(
            List.<String>of(),
            List.of(""),
            List.of("bad id"),
            List.of("a,b"),
            List.of("한글"),
            List.of("bad\nvalue"),
            List.of("a".repeat(65)),
            List.of("valid", "valid"))) {
      var request = new MockHttpServletRequest();
      invalid.forEach(value -> request.addHeader(RequestIdFilter.HEADER, value));
      var response = new MockHttpServletResponse();
      filter.doFilter(
          request,
          response,
          (req, res) ->
              assertEquals(req.getAttribute(RequestIdFilter.ATTRIBUTE), MDC.get("request_id")));
      String generated = response.getHeader(RequestIdFilter.HEADER);
      assertEquals(generated, UUID.fromString(generated).toString());
      assertEquals(generated, request.getAttribute(RequestIdFilter.ATTRIBUTE));
      assertNull(MDC.get("request_id"));
    }
  }

  @Test
  void exceptionsRestorePreviousMdcAndDoNotLeakTheFailedRequest() {
    for (String previous : new String[] {null, "outer-scope"}) {
      if (previous == null) {
        MDC.remove("request_id");
      } else {
        MDC.put("request_id", previous);
      }
      var request = new MockHttpServletRequest();
      request.addHeader(RequestIdFilter.HEADER, "inner-request");
      assertThrows(
          ServletException.class,
          () ->
              filter.doFilter(
                  request,
                  new MockHttpServletResponse(),
                  (req, res) -> {
                    assertEquals("inner-request", MDC.get("request_id"));
                    throw new ServletException("failed");
                  }));
      assertEquals(previous, MDC.get("request_id"));
    }
  }

  @Test
  void asyncAndErrorRedispatchReuseTheAttributeAfterOriginalScopeEnds() throws Exception {
    var request = new MockHttpServletRequest();
    var response = new MockHttpServletResponse();
    filter.doFilter(request, response, (req, res) -> {});
    String original = response.getHeader(RequestIdFilter.HEADER);
    request.addHeader(RequestIdFilter.HEADER, "changed-header");
    for (var dispatch : List.of(DispatcherType.ASYNC, DispatcherType.ERROR)) {
      request.setDispatcherType(dispatch);
      if (dispatch == DispatcherType.ERROR) {
        request.setAttribute("jakarta.servlet.error.request_uri", "/original");
      }
      var redispatchResponse = new MockHttpServletResponse();
      filter.doFilter(
          request,
          redispatchResponse,
          (req, res) -> {
            assertEquals(original, req.getAttribute(RequestIdFilter.ATTRIBUTE));
            assertEquals(original, MDC.get("request_id"));
          });
      assertEquals(original, redispatchResponse.getHeader(RequestIdFilter.HEADER));
      assertNull(MDC.get("request_id"));
    }
  }
}
