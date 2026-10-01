package com.teamdaisy.server.identity.web;

import com.teamdaisy.server.common.error.DaisyException;
import com.teamdaisy.server.common.error.ErrorCode;
import com.teamdaisy.server.identity.auth.AuthPrincipal;
import org.springframework.core.MethodParameter;
import org.springframework.stereotype.Component;
import org.springframework.web.bind.support.WebDataBinderFactory;
import org.springframework.web.context.request.NativeWebRequest;
import org.springframework.web.context.request.RequestAttributes;
import org.springframework.web.method.support.HandlerMethodArgumentResolver;
import org.springframework.web.method.support.ModelAndViewContainer;

/** {@link CurrentAccount} 파라미터에 필터가 넣어 둔 주체를 꽂아 줘요. */
@Component
public class CurrentAccountArgumentResolver implements HandlerMethodArgumentResolver {
  @Override
  public boolean supportsParameter(MethodParameter parameter) {
    return parameter.hasParameterAnnotation(CurrentAccount.class)
        && AuthPrincipal.class.isAssignableFrom(parameter.getParameterType());
  }

  @Override
  public Object resolveArgument(
      MethodParameter parameter,
      ModelAndViewContainer container,
      NativeWebRequest request,
      WebDataBinderFactory binderFactory) {
    Object principal =
        request.getAttribute(BearerAuthFilter.PRINCIPAL_ATTRIBUTE, RequestAttributes.SCOPE_REQUEST);
    if (principal instanceof AuthPrincipal authPrincipal) {
      return authPrincipal;
    }
    // 필터를 지나지 않은 경로에서 주체를 요구한 경우예요. 익명으로 처리하지 않아요.
    throw new DaisyException(ErrorCode.UNAUTHENTICATED);
  }
}
