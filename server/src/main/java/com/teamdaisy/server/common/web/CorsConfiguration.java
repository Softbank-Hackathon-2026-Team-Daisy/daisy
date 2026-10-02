package com.teamdaisy.server.common.web;

import java.util.List;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.web.servlet.FilterRegistrationBean;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.core.Ordered;
import org.springframework.web.cors.UrlBasedCorsConfigurationSource;
import org.springframework.web.filter.CorsFilter;

/**
 * 웹 대시보드가 쓰는 CORS 설정이에요 (계약 v0.3 §4 웹 연결 설정).
 *
 * <p>허용 origin 은 환경변수로 받아요. 와일드카드를 쓰지 않아요.
 */
@Configuration
public class CorsConfiguration {
  private final List<String> allowedOrigins;

  public CorsConfiguration(
      @Value("${daisy.cors.allowed-origins:http://localhost:5173,http://localhost:5174}")
          List<String> allowedOrigins) {
    this.allowedOrigins = allowedOrigins;
  }

  @Bean
  public FilterRegistrationBean<CorsFilter> corsFilter() {
    var cors = new org.springframework.web.cors.CorsConfiguration();
    cors.setAllowedOrigins(allowedOrigins);
    cors.setAllowedMethods(List.of("GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"));
    cors.setAllowedHeaders(
        List.of(
            "Authorization", "Content-Type", "Last-Event-ID", "Idempotency-Key", "X-Request-ID"));
    cors.setExposedHeaders(List.of("X-Request-ID"));
    cors.setAllowCredentials(false);
    cors.setMaxAge(3600L);
    var source = new UrlBasedCorsConfigurationSource();
    source.registerCorsConfiguration("/**", cors);
    var registration = new FilterRegistrationBean<>(new CorsFilter(source));
    // BearerAuthFilter(+20)가 거절하는 응답에도 CORS 헤더를 붙여요.
    registration.setOrder(Ordered.HIGHEST_PRECEDENCE + 10);
    return registration;
  }
}
