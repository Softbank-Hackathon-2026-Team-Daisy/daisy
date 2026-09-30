package com.teamdaisy.server.jenkins.application;

import static org.assertj.core.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.PropertyNamingStrategies;
import com.teamdaisy.server.ai.application.AiUsageService;
import com.teamdaisy.server.common.error.DaisyException;
import com.teamdaisy.server.common.error.ErrorCode;
import com.teamdaisy.server.common.json.CanonicalJson;
import com.teamdaisy.server.deployment.application.DeploymentExecutionService;
import com.teamdaisy.server.history.application.JenkinsReceiptService;
import com.teamdaisy.server.jenkins.api.JenkinsCallbackController;
import com.teamdaisy.server.jenkins.application.ExecutionCallbackAccess.VerifiedSender;
import com.teamdaisy.server.jenkins.application.JenkinsCallbackService.Envelope;
import com.teamdaisy.server.jenkins.application.JenkinsCommandService.CommandScope;
import com.teamdaisy.server.script.application.ScriptService;
import java.nio.charset.StandardCharsets;
import java.time.Instant;
import java.util.Set;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.mock.web.MockHttpServletRequest;

class JenkinsCallbackServiceTest {
  private final ObjectMapper mapper = new ObjectMapper().findAndRegisterModules().setPropertyNamingStrategy(PropertyNamingStrategies.SNAKE_CASE);
  @SuppressWarnings("unchecked")
  private final ObjectProvider<ExecutionCallbackAccess> access = mock(ObjectProvider.class);
  private final JenkinsCommandService commands = mock(JenkinsCommandService.class);
  private final DeploymentExecutionService deployments = mock(DeploymentExecutionService.class);
  private final JenkinsReceiptService history = mock(JenkinsReceiptService.class);
  private final JenkinsCallbackService service = new JenkinsCallbackService(access, commands, deployments,
      mock(ScriptService.class), mock(AiUsageService.class), history, mapper, new CanonicalJson(mapper));
  private final VerifiedSender sender = new VerifiedSender("ci", Set.of("daisy/prepare"));

  @Test
  void missingTrustPortFailsBeforeReadingBody() throws Exception {
    var request = mock(jakarta.servlet.http.HttpServletRequest.class);
    assertThatThrownBy(() -> new JenkinsCallbackController(service).receive(request))
        .isInstanceOfSatisfying(DaisyException.class, e -> assertThat(e.errorCode()).isEqualTo(ErrorCode.FORBIDDEN));
    verify(request, never()).getInputStream();
    verifyNoInteractions(commands, deployments);
  }

  @Test
  void bodyIsBoundedEvenWhenChunkedAndUnknownFieldsAndDuplicateKeysFail() {
    var chunked = new MockHttpServletRequest() {
      @Override public long getContentLengthLong() { return -1; }
    };
    chunked.setContent(new byte[JenkinsCallbackService.MAX_BODY_BYTES + 1]);
    assertThatThrownBy(() -> service.read(chunked)).isInstanceOf(DaisyException.class);
    for (String body : new String[] {"{\"source\":\"caller\"}", "{\"kind\":\"build\",\"kind\":\"state\"}", "{} {}"}) {
      var request = new MockHttpServletRequest();
      request.setContent(body.getBytes(StandardCharsets.UTF_8));
      assertThatThrownBy(() -> service.read(request)).isInstanceOf(DaisyException.class);
    }
    verifyNoInteractions(commands);
  }

  @Test
  void deniedJobAndMalformedScopeNeverBind() {
    var valid = envelope("state", "dt_1", mapper.createObjectNode().put("status", "generating").put("attempt", 1));
    assertThatThrownBy(() -> service.receive(new VerifiedSender("ci", Set.of("other/job")), valid)).isInstanceOf(DaisyException.class);
    assertThatThrownBy(() -> service.receive(sender, envelope("build", "dt_1", mapper.createObjectNode()))).isInstanceOf(DaisyException.class);
    assertThatThrownBy(() -> service.receive(sender, envelope("state", "dt_1", mapper.createObjectNode().put("extra", true)))).isInstanceOf(DaisyException.class);
    verifyNoInteractions(commands, deployments);
  }

  @Test
  void stateDispatchInjectsStoredScopeAndTrustedSource() {
    var scope = new CommandScope("job_1", "dep_stored", "prj_stored", "req_1", "prepare", null,
        "ci", "daisy/prepare", "dispatching", "unknown", null, null, mapper.createObjectNode());
    when(commands.bindCallback("job_1", "req_1", "ci", "daisy/prepare", null, 7L, "dt_1")).thenReturn(scope);
    Envelope event = envelope("state", "dt_1", mapper.createObjectNode().put("status", "generating").put("attempt", 1));
    assertThat(service.receive(sender, event).executionId()).isEqualTo("job_1");
    var result = ArgumentCaptor.forClass(DeploymentExecutionService.StateResult.class);
    verify(deployments).acceptState(result.capture());
    assertThat(result.getValue().projectId()).isEqualTo("prj_stored");
    assertThat(result.getValue().deploymentId()).isEqualTo("dep_stored");
    assertThat(result.getValue().source()).startsWith("jenkins:sha256:");
    assertThat(result.getValue().sourceEventId()).isEqualTo("event_1");
  }

  private Envelope envelope(String kind, String target, com.fasterxml.jackson.databind.JsonNode payload) {
    return new Envelope("job_1", "req_1", "daisy/prepare", 7L, null, "event_1", kind.equals("build") ? null : 1L,
        Instant.parse("2026-10-01T00:00:00Z"), target, kind, payload);
  }
}
