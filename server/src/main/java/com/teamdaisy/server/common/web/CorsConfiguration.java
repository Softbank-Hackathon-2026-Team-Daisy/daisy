package com.teamdaisy.server.common.web;

import java.util.List;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.servlet.config.annotation.CorsRegistry;
import org.springframework.web.servlet.config.annotation.WebMvcConfigurer;

/**
 * 웹 대시보드가 쓰는 CORS 설정이에요 (계약 v0.3 §4 웹 연결 설정).
 *
 * <p>허용 origin 은 환경변수로 받아요. 와일드카드를 쓰지 않아요.
 */
@Configuration
public class CorsConfiguration implements WebMvcConfigurer {
  private final List<String> allowedOrigins;

  public CorsConfiguration(
      @Value("${daisy.cors.allowed-origins:http://localhost:5173,http://localhost:5174}")
          List<String> allowedOrigins) {
    this.allowedOrigins = allowedOrigins;
  }

  @Override
  public void addCorsMappings(CorsRegistry registry) {
    registry
        .addMapping("/**")
        .allowedOrigins(allowedOrigins.toArray(String[]::new))
        .allowedMethods("GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS")
        .allowedHeaders(
            "Authorization", "Content-Type", "Last-Event-ID", "Idempotency-Key", "X-Request-ID")
        .exposedHeaders("X-Request-ID")
        .allowCredentials(false)
        .maxAge(3600);
  }
}
