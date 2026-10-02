package com.teamdaisy.server.project.web;

import com.fasterxml.jackson.databind.DeserializationFeature;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.teamdaisy.server.common.error.DaisyException;
import com.teamdaisy.server.common.error.ErrorCode;
import com.teamdaisy.server.identity.auth.JenkinsCallbackTokenAccess;
import com.teamdaisy.server.project.application.BuildReceipt;
import com.teamdaisy.server.project.application.BuildRegistry.BuildReport;
import com.teamdaisy.server.project.application.BuildRegistry.Recorded;
import io.swagger.v3.oas.annotations.Hidden;
import jakarta.servlet.http.HttpServletRequest;
import java.io.IOException;
import java.time.Instant;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * Jenkins CI 빌드 결과 수신이에요 ({@code POST /internal/jenkins/builds}, #35).
 *
 * <p>사용자 로그인이 아니라 Jenkins 콜백과 같은 서비스 토큰으로 지켜요. 콜백과 같은 설정으로 켜고 꺼요. 본문은 64 KiB 까지이고 모르는 필드는 400 이에요 —
 * 이름을 잘못 보내면 조용히 버려지지 않게요.
 */
@Hidden
@RestController
@ConditionalOnProperty(name = "daisy.jenkins.callbacks-enabled", havingValue = "true")
public class JenkinsBuildController {
  static final int MAX_BODY_BYTES = 64 * 1024;

  private final JenkinsCallbackTokenAccess token;
  private final BuildReceipt receipt;
  private final ObjectMapper strict;

  public JenkinsBuildController(
      JenkinsCallbackTokenAccess token, BuildReceipt receipt, ObjectMapper mapper) {
    this.token = token;
    this.receipt = receipt;
    this.strict = mapper.copy().enable(DeserializationFeature.FAIL_ON_UNKNOWN_PROPERTIES);
  }

  /** #35 인프라 JSON 이에요. 이름은 {@code BuildReport} 와 같아요. */
  record BuildBody(
      String projectId,
      String source,
      String externalBuildId,
      String commitSha,
      String branch,
      String status,
      JsonNode imageRefs,
      String runUrl,
      Instant startedAt,
      Instant finishedAt,
      String errorSummary) {

    BuildReport toReport() {
      return new BuildReport(
          projectId,
          source,
          externalBuildId,
          commitSha,
          branch,
          status,
          imageRefs,
          runUrl,
          startedAt,
          finishedAt,
          errorSummary);
    }
  }

  /** 저장 결과예요. 같은 결과를 다시 받으면 {@code changed} 가 false 예요. */
  public record Received(String sourceVersionId, boolean changed) {}

  @PostMapping(path = "/internal/jenkins/builds", consumes = "application/json")
  public Received receive(HttpServletRequest request) {
    token.requireToken(request);
    BuildBody body = read(request);
    Recorded recorded = receipt.receive(body.toReport());
    return new Received(recorded.sourceVersionId(), recorded.changed());
  }

  private BuildBody read(HttpServletRequest request) {
    if (request.getContentLengthLong() > MAX_BODY_BYTES) {
      throw new DaisyException(ErrorCode.VALIDATION_FAILED);
    }
    try {
      byte[] bytes = request.getInputStream().readNBytes(MAX_BODY_BYTES + 1);
      if (bytes.length > MAX_BODY_BYTES) {
        throw new DaisyException(ErrorCode.VALIDATION_FAILED);
      }
      BuildBody body = strict.readValue(bytes, BuildBody.class);
      if (body == null) {
        throw new DaisyException(ErrorCode.VALIDATION_FAILED);
      }
      return body;
    } catch (IOException error) {
      throw new DaisyException(ErrorCode.VALIDATION_FAILED);
    }
  }
}
