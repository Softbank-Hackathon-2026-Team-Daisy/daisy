package com.teamdaisy.server.identity.web;

import org.springdoc.core.utils.SpringDocUtils;
import org.springframework.context.annotation.Configuration;

/**
 * {@code @CurrentAccount} 를 OpenAPI 문서에서 숨겨요.
 *
 * <p>이 애너테이션은 {@link CurrentAccountArgumentResolver} 가 인증 필터가 넣어 둔 주체로 채워요. 요청에서 받는 값이 아니에요. 그런데
 * springdoc 은 알려진 애너테이션이 아닌 핸들러 인자를 기본적으로 쿼리 파라미터로 봐서, 설정이 없으면 모든 보호 경로에 {@code principal} 이 쿼리로
 * 올라가요. 소비자에게 {@code ?principal=...} 을 보내라고 알려주는 셈이에요.
 *
 * <p>이슈 #13 의 완료 기준이 "받은 건 OpenAPI 에 나와 있어요" 라서, 문서가 틀리면 계약이 틀린 것과 같아요.
 *
 * <p>정적 초기화를 쓰는 것은 springdoc 이 빈 생성보다 먼저 이 설정을 읽기 때문이에요.
 */
@Configuration
public class CurrentAccountOpenApiConfiguration {
  static {
    SpringDocUtils.getConfig().addAnnotationsToIgnore(CurrentAccount.class);
  }
}
