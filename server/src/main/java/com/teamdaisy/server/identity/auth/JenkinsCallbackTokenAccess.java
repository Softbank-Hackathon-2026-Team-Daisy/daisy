package com.teamdaisy.server.identity.auth;

import com.teamdaisy.server.common.error.DaisyException;
import com.teamdaisy.server.common.error.ErrorCode;
import com.teamdaisy.server.jenkins.application.ExecutionCallbackAccess;
import jakarta.servlet.http.HttpServletRequest;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.LinkedHashSet;
import java.util.Set;
import org.springframework.core.env.Environment;
import org.springframework.stereotype.Component;

/**
 * Jenkins 콜백의 서비스 인증이에요 ({@code ExecutionCallbackAccess}, #35).
 *
 * <p>사용자 로그인(Bearer)이 아니라 Jenkins 와 서버가 나눠 가진 토큰 하나로 확인해요. 토큰 설정이 없으면 콜백 전체를 403 으로 막고, 헤더가 없거나 다르면
 * 401 이에요. 비교는 상수 시간이고 토큰 값은 로그에 남기지 않아요.
 *
 * <p>{@code instanceId} 와 허용 Job 은 명령 서비스가 쓰는 설정을 그대로 읽어요. 다르면 승환의 수신부가 실행 범위를 맞추지 못해요.
 */
@Component
public class JenkinsCallbackTokenAccess implements ExecutionCallbackAccess {
  public static final String HEADER = "X-Daisy-Jenkins-Token";

  private final Environment env;

  public JenkinsCallbackTokenAccess(Environment env) {
    this.env = env;
  }

  @Override
  public VerifiedSender verify(HttpServletRequest request) {
    requireToken(request);
    String instance = env.getProperty("daisy.jenkins.instance-id", "proposal-jenkins");
    Set<String> jobs = new LinkedHashSet<>();
    jobs.add(env.getProperty("daisy.jenkins.operation-jobs.prepare", "daisy-cd-plan"));
    jobs.add(env.getProperty("daisy.jenkins.operation-jobs.replan", "daisy-cd-plan"));
    jobs.add(env.getProperty("daisy.jenkins.operation-jobs.apply", "daisy-cd-apply"));
    return new VerifiedSender(instance, jobs);
  }

  /** 헤더 토큰이 서버 설정과 같은지 봐요. CI 빌드 수신도 같은 토큰을 써요. */
  public void requireToken(HttpServletRequest request) {
    String expected = env.getProperty("daisy.jenkins.callback-token", "");
    if (expected.isBlank()) {
      throw new DaisyException(ErrorCode.FORBIDDEN);
    }
    String presented = request.getHeader(HEADER);
    if (presented == null || presented.isEmpty() || !sameSecret(expected, presented)) {
      throw new DaisyException(ErrorCode.UNAUTHENTICATED);
    }
  }

  /** 두 값을 같은 길이의 해시로 만든 뒤 비교해서, 길이나 앞부분 일치가 응답 시간에 드러나지 않게 해요. */
  static boolean sameSecret(String expected, String presented) {
    return MessageDigest.isEqual(sha256(expected), sha256(presented));
  }

  private static byte[] sha256(String value) {
    try {
      return MessageDigest.getInstance("SHA-256").digest(value.getBytes(StandardCharsets.UTF_8));
    } catch (NoSuchAlgorithmException error) {
      throw new IllegalStateException("SHA-256 을 쓸 수 없어요", error);
    }
  }
}
