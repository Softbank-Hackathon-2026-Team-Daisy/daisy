package com.teamdaisy.server.common.web;

import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import java.io.IOException;
import java.util.UUID;
import java.util.regex.Pattern;
import org.slf4j.MDC;
import org.springframework.core.Ordered;
import org.springframework.core.annotation.Order;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

@Component
@Order(Ordered.HIGHEST_PRECEDENCE)
public class RequestIdFilter extends OncePerRequestFilter {
  public static final String HEADER = "X-Request-ID";
  public static final String ATTRIBUTE = RequestIdFilter.class.getName() + ".requestId";
  private static final Pattern VALID_ID = Pattern.compile("[A-Za-z0-9._-]{1,64}");

  @Override
  protected boolean shouldNotFilterAsyncDispatch() {
    return false;
  }

  @Override
  protected boolean shouldNotFilterErrorDispatch() {
    return false;
  }

  @Override
  protected void doFilterInternal(
      HttpServletRequest request, HttpServletResponse response, FilterChain chain)
      throws ServletException, IOException {
    String requestId = (String) request.getAttribute(ATTRIBUTE);
    if (requestId == null) {
      var headers = request.getHeaders(HEADER);
      String candidate =
          headers != null && headers.hasMoreElements() ? headers.nextElement() : null;
      requestId =
          candidate != null && !headers.hasMoreElements() && VALID_ID.matcher(candidate).matches()
              ? candidate
              : UUID.randomUUID().toString();
      request.setAttribute(ATTRIBUTE, requestId);
    }
    response.setHeader(HEADER, requestId);
    String previous = MDC.get("request_id");
    MDC.put("request_id", requestId);
    try {
      chain.doFilter(request, response);
    } finally {
      if (previous == null) {
        MDC.remove("request_id");
      } else {
        MDC.put("request_id", previous);
      }
    }
  }
}
