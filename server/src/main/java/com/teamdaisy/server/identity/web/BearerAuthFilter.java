package com.teamdaisy.server.identity.web;

import com.teamdaisy.server.common.error.DaisyException;
import com.teamdaisy.server.common.error.ErrorCode;
import com.teamdaisy.server.identity.auth.AuthPrincipal;
import com.teamdaisy.server.identity.auth.AuthService;
import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import java.io.IOException;
import java.util.List;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.core.Ordered;
import org.springframework.core.annotation.Order;
import org.springframework.http.HttpHeaders;
import org.springframework.stereotype.Component;
import org.springframework.util.AntPathMatcher;
import org.springframework.web.filter.OncePerRequestFilter;
import org.springframework.web.servlet.HandlerExceptionResolver;

/**
 * {@code Authorization: Bearer <token>} 을 확인해 요청에 주체를 붙여요.
 *
 * <p>REST 와 SSE 에 같은 방식을 써요. 쿠키는 받지 않아요.
 *
 * <p>필터에서 던진 예외는 {@code @RestControllerAdvice} 가 받지 못해요. 그래서 공통 예외 처리기로 직접 넘겨서, 인증 실패도 다른 오류와 같은 응답
 * 모양으로 나가게 해요.
 */
@Component
@Order(Ordered.HIGHEST_PRECEDENCE + 20)
public class BearerAuthFilter extends OncePerRequestFilter {
  /** 요청에 담기는 주체. 컨트롤러는 {@link CurrentAccountArgumentResolver} 로 받아요. */
  public static final String PRINCIPAL_ATTRIBUTE = BearerAuthFilter.class.getName() + ".principal";

  private static final String BEARER = "Bearer ";
  private static final List<String> PUBLIC_PATHS =
      List.of(
          "/auth/token",
          "/actuator/health",
          "/actuator/health/**",
          "/v3/api-docs",
          "/v3/api-docs/**",
          "/swagger-ui.html",
          "/swagger-ui/**");

  private final AuthService authService;
  private final HandlerExceptionResolver exceptionResolver;
  private final AntPathMatcher matcher = new AntPathMatcher();

  public BearerAuthFilter(
      AuthService authService,
      @Qualifier("handlerExceptionResolver") HandlerExceptionResolver exceptionResolver) {
    this.authService = authService;
    this.exceptionResolver = exceptionResolver;
  }

  @Override
  protected boolean shouldNotFilter(HttpServletRequest request) {
    if ("OPTIONS".equalsIgnoreCase(request.getMethod())) {
      return true;
    }
    String path = request.getRequestURI();
    return PUBLIC_PATHS.stream().anyMatch(pattern -> matcher.match(pattern, path));
  }

  @Override
  protected void doFilterInternal(
      HttpServletRequest request, HttpServletResponse response, FilterChain chain)
      throws ServletException, IOException {
    AuthPrincipal principal;
    try {
      principal = authenticate(request);
    } catch (DaisyException exception) {
      exceptionResolver.resolveException(request, response, null, exception);
      return;
    }
    request.setAttribute(PRINCIPAL_ATTRIBUTE, principal);
    chain.doFilter(request, response);
  }

  private AuthPrincipal authenticate(HttpServletRequest request) {
    String header = request.getHeader(HttpHeaders.AUTHORIZATION);
    if (header == null || !header.startsWith(BEARER)) {
      throw new DaisyException(ErrorCode.UNAUTHENTICATED);
    }
    String token = header.substring(BEARER.length()).trim();
    if (token.isEmpty()) {
      throw new DaisyException(ErrorCode.UNAUTHENTICATED);
    }
    return authService.resolve(token);
  }
}
