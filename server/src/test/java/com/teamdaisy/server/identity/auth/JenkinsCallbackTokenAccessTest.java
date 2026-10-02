package com.teamdaisy.server.identity.auth;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import com.teamdaisy.server.common.error.DaisyException;
import com.teamdaisy.server.common.error.ErrorCode;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.mock.env.MockEnvironment;
import org.springframework.mock.web.MockHttpServletRequest;

/** Jenkins 콜백 서비스 인증 규칙을 고정해요 (server/SPEC.md 「Jenkins 콜백 인증」). */
class JenkinsCallbackTokenAccessTest {
  private static final String TOKEN = "test-only-callback-token";

  private static JenkinsCallbackTokenAccess access(String token) {
    MockEnvironment env =
        new MockEnvironment().withProperty("daisy.jenkins.instance-id", "unibloom-onprem");
    if (token != null) {
      env.setProperty("daisy.jenkins.callback-token", token);
    }
    return new JenkinsCallbackTokenAccess(env);
  }

  private static MockHttpServletRequest request(String header) {
    MockHttpServletRequest request =
        new MockHttpServletRequest("POST", "/internal/jenkins/callbacks");
    if (header != null) {
      request.addHeader(JenkinsCallbackTokenAccess.HEADER, header);
    }
    return request;
  }

  private static void assertCode(Runnable call, ErrorCode code) {
    assertThatThrownBy(call::run)
        .isInstanceOf(DaisyException.class)
        .extracting(exception -> ((DaisyException) exception).errorCode())
        .isEqualTo(code);
  }

  @Test
  @DisplayName("맞는 토큰이면 설정의 instanceId 와 허용 Job 으로 통과해요")
  void validTokenPasses() {
    var sender = access(TOKEN).verify(request(TOKEN));

    assertThat(sender.instanceId()).isEqualTo("unibloom-onprem");
    assertThat(sender.permittedJobs()).containsExactlyInAnyOrder("daisy-cd-plan", "daisy-cd-apply");
  }

  @Test
  @DisplayName("헤더가 없거나 비었거나 다르면 401 이에요")
  void missingOrWrongTokenIsUnauthenticated() {
    assertCode(() -> access(TOKEN).verify(request(null)), ErrorCode.UNAUTHENTICATED);
    assertCode(() -> access(TOKEN).verify(request("")), ErrorCode.UNAUTHENTICATED);
    assertCode(() -> access(TOKEN).verify(request(TOKEN + "x")), ErrorCode.UNAUTHENTICATED);
    assertCode(() -> access(TOKEN).verify(request("test-only")), ErrorCode.UNAUTHENTICATED);
  }

  @Test
  @DisplayName("서버에 토큰 설정이 없거나 비면 맞는 헤더를 보내도 403 이에요")
  void noConfiguredTokenIsForbidden() {
    assertCode(() -> access(null).verify(request(TOKEN)), ErrorCode.FORBIDDEN);
    assertCode(() -> access("  ").verify(request("  ")), ErrorCode.FORBIDDEN);
  }

  @Test
  @DisplayName("Job 이름은 명령 서비스 설정을 따라가요")
  void jobsFollowOperationSettings() {
    MockEnvironment env =
        new MockEnvironment()
            .withProperty("daisy.jenkins.callback-token", TOKEN)
            .withProperty("daisy.jenkins.operation-jobs.apply", "team/daisy-cd-apply");
    var sender = new JenkinsCallbackTokenAccess(env).verify(request(TOKEN));

    assertThat(sender.permittedJobs())
        .containsExactlyInAnyOrder("daisy-cd-plan", "team/daisy-cd-apply");
    assertThat(sender.instanceId()).isEqualTo("proposal-jenkins");
  }

  @Test
  @DisplayName("비교는 해시로 같은 길이로 만든 뒤 해요")
  void sameSecret() {
    assertThat(JenkinsCallbackTokenAccess.sameSecret("abc", "abc")).isTrue();
    assertThat(JenkinsCallbackTokenAccess.sameSecret("abc", "abd")).isFalse();
    assertThat(JenkinsCallbackTokenAccess.sameSecret("abc", "abcd")).isFalse();
  }
}
