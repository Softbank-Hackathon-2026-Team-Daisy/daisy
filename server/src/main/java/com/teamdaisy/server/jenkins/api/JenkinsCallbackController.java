package com.teamdaisy.server.jenkins.api;

import com.teamdaisy.server.jenkins.application.JenkinsCallbackService;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.enums.SecuritySchemeIn;
import io.swagger.v3.oas.annotations.enums.SecuritySchemeType;
import io.swagger.v3.oas.annotations.media.Content;
import io.swagger.v3.oas.annotations.media.Schema;
import io.swagger.v3.oas.annotations.parameters.RequestBody;
import io.swagger.v3.oas.annotations.security.SecurityRequirement;
import io.swagger.v3.oas.annotations.security.SecurityScheme;
import jakarta.servlet.http.HttpServletRequest;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RestController;

/** Internal service endpoint; authentication and bounded strict parsing remain in the service. */
@RestController
@ConditionalOnProperty(name = "daisy.jenkins.callbacks-enabled", havingValue = "true")
@SecurityScheme(
    name = "jenkinsCallbackToken",
    type = SecuritySchemeType.APIKEY,
    in = SecuritySchemeIn.HEADER,
    paramName = "X-Daisy-Jenkins-Token")
@SecurityRequirement(name = "jenkinsCallbackToken")
public class JenkinsCallbackController {
  private final JenkinsCallbackService callbacks;

  public JenkinsCallbackController(JenkinsCallbackService callbacks) {
    this.callbacks = callbacks;
  }

  @PostMapping(path = "/internal/jenkins/callbacks", consumes = "application/json")
  @Operation(
      summary = "Jenkins 배포 결과 수신 — 내부 서비스 토큰 필요",
      description = "payload는 kind별 수신 계약을 따라요. 사용자 Bearer 토큰으로 호출하지 않아요.",
      requestBody =
          @RequestBody(
              required = true,
              content =
                  @Content(
                      mediaType = "application/json",
                      schema = @Schema(implementation = JenkinsCallbackService.Envelope.class))))
  public JenkinsCallbackService.Receipt receive(HttpServletRequest request) {
    var sender = callbacks.authenticate(request);
    var envelope = callbacks.read(request);
    // Spring's service transaction commits before the controller returns the ACK.
    return callbacks.receive(sender, envelope);
  }
}
