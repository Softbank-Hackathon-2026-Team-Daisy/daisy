package com.teamdaisy.server.common.web;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.mock;

import com.teamdaisy.server.identity.auth.AuthService;
import com.teamdaisy.server.identity.web.BearerAuthFilter;
import java.util.List;
import org.junit.jupiter.api.Test;
import org.springframework.core.annotation.Order;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.mock.web.MockHttpServletResponse;
import org.springframework.web.servlet.ModelAndView;

class CorsConfigurationTest {
  private final CorsConfiguration configuration =
      new CorsConfiguration(List.of("http://localhost:5173"));

  @Test
  void corsRunsBeforeBearerAndKeepsHeadersOnAuthenticationFailure() throws Exception {
    var registration = configuration.corsFilter();
    assertTrue(registration.getOrder() < BearerAuthFilter.class.getAnnotation(Order.class).value());
    var auth =
        new BearerAuthFilter(
            mock(AuthService.class),
            (request, response, handler, error) -> {
              response.setStatus(401);
              return new ModelAndView();
            });
    var request = new MockHttpServletRequest("GET", "/projects");
    request.addHeader("Origin", "http://localhost:5173");
    var response = new MockHttpServletResponse();
    registration
        .getFilter()
        .doFilter(
            request,
            response,
            (req, res) ->
                auth.doFilter(
                    req, res, (ignoredReq, ignoredRes) -> fail("Authentication required")));
    assertEquals(401, response.getStatus());
    assertEquals("http://localhost:5173", response.getHeader("Access-Control-Allow-Origin"));
  }

  @Test
  void preflightAllowsContractHeadersButRejectsUnknownOrigin() throws Exception {
    for (String origin : List.of("http://localhost:5173", "https://untrusted.example")) {
      var request = new MockHttpServletRequest("OPTIONS", "/projects");
      request.addHeader("Origin", origin);
      request.addHeader("Access-Control-Request-Method", "POST");
      request.addHeader(
          "Access-Control-Request-Headers", "authorization,last-event-id,idempotency-key");
      var response = new MockHttpServletResponse();
      configuration
          .corsFilter()
          .getFilter()
          .doFilter(
              request, response, (req, res) -> fail("Preflight must finish before authentication"));
      if (origin.equals("http://localhost:5173")) {
        assertEquals(200, response.getStatus());
        assertTrue(response.getHeader("Access-Control-Allow-Headers").contains("idempotency-key"));
        assertNull(response.getHeader("Access-Control-Allow-Credentials"));
      } else {
        assertEquals(403, response.getStatus());
        assertNull(response.getHeader("Access-Control-Allow-Origin"));
      }
    }
  }
}
