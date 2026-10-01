package com.teamdaisy.server.identity.web;

import java.util.List;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.method.support.HandlerMethodArgumentResolver;
import org.springframework.web.servlet.config.annotation.WebMvcConfigurer;

/** 인증 주체 파라미터 해석기를 등록해요. */
@Configuration
public class WebMvcConfiguration implements WebMvcConfigurer {
  private final CurrentAccountArgumentResolver currentAccountArgumentResolver;

  public WebMvcConfiguration(CurrentAccountArgumentResolver currentAccountArgumentResolver) {
    this.currentAccountArgumentResolver = currentAccountArgumentResolver;
  }

  @Override
  public void addArgumentResolvers(List<HandlerMethodArgumentResolver> resolvers) {
    resolvers.add(currentAccountArgumentResolver);
  }
}
