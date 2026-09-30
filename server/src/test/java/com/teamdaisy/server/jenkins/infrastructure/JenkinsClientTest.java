package com.teamdaisy.server.jenkins.infrastructure;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.sun.net.httpserver.HttpServer;
import java.net.InetSocketAddress;
import java.nio.charset.StandardCharsets;
import java.util.Map;
import java.util.concurrent.atomic.AtomicInteger;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.mock.env.MockEnvironment;

class JenkinsClientTest {
  private HttpServer server;
  private MockEnvironment env;
  private String origin;

  @BeforeEach
  void setup() throws Exception {
    server = HttpServer.create(new InetSocketAddress("127.0.0.1", 0), 0);
    origin = "http://127.0.0.1:" + server.getAddress().getPort() + "/jenkins/";
    env = new MockEnvironment().withProperty("daisy.jenkins.enabled", "true")
        .withProperty("daisy.jenkins.base-url", origin)
        .withProperty("daisy.jenkins.jobs", "folder/my job")
        .withProperty("daisy.jenkins.user", "test-user")
        .withProperty("daisy.jenkins.token", "test-token");
    server.start();
  }

  @AfterEach
  void stop() { server.stop(0); }

  private JenkinsClient client() { return new JenkinsClient(env, new ObjectMapper()); }

  @Test
  void submissionEncodesFoldersAndValidatesLocation() {
    server.createContext("/jenkins/job/folder/job/my job/buildWithParameters", exchange -> {
      assertThat(exchange.getRequestURI().getRawPath()).contains("my%20job");
      assertThat(new String(exchange.getRequestBody().readAllBytes(), StandardCharsets.UTF_8))
          .contains("request_id=cmd-1", "payload=");
      exchange.getResponseHeaders().add("Location", origin + "queue/item/17/");
      exchange.sendResponseHeaders(201, -1);
      exchange.close();
    });
    assertThat(client().submit("folder/my job", "cmd-1", Map.of("operation", "prepare")).queueId())
        .isEqualTo(17);
  }

  @Test
  void externalLocationAndRedirectNeverFetchDestination() {
    AtomicInteger destinationCalls = new AtomicInteger();
    server.createContext("/destination", exchange -> { destinationCalls.incrementAndGet(); exchange.close(); });
    server.createContext("/jenkins/job/folder/job/my job/buildWithParameters", exchange -> {
      exchange.getResponseHeaders().add("Location", "http://localhost:" + server.getAddress().getPort() + "/destination");
      exchange.sendResponseHeaders(201, -1); exchange.close();
    });
    assertThatThrownBy(() -> client().submit("folder/my job", "cmd-1", Map.of()))
        .isInstanceOf(JenkinsClient.RequestException.class);
    assertThat(destinationCalls.get()).isZero();
  }

  @Test
  void missingRequestIsUnknownAndQueryCanBeEncoded() {
    server.createContext("/jenkins/queue/api/json", exchange -> {
      byte[] body = "{\"items\":[]}".getBytes(StandardCharsets.UTF_8);
      exchange.sendResponseHeaders(200, body.length); exchange.getResponseBody().write(body); exchange.close();
    });
    server.createContext("/jenkins/job/folder/job/my job/api/json", exchange -> {
      byte[] body = "{\"builds\":[]}".getBytes(StandardCharsets.UTF_8);
      exchange.sendResponseHeaders(200, body.length); exchange.getResponseBody().write(body); exchange.close();
    });
    assertThat(client().findRequest("folder/my job", "cmd-1").state())
        .isEqualTo(JenkinsClient.LookupState.UNKNOWN);
  }

  @Test
  void progressiveLogPreservesBytesAndJenkinsCursor() {
    byte[] utf8 = "가".getBytes(StandardCharsets.UTF_8);
    server.createContext("/jenkins/job/folder/job/my job/7/logText/progressiveText", exchange -> {
      exchange.getResponseHeaders().add("X-Text-Size", "103");
      exchange.getResponseHeaders().add("X-More-Data", "true");
      exchange.sendResponseHeaders(200, utf8.length); exchange.getResponseBody().write(utf8); exchange.close();
    });
    var chunk = client().progressiveLog("folder/my job", 7, 100);
    assertThat(chunk.bytes()).isEqualTo(utf8);
    assertThat(chunk.nextOffset()).isEqualTo(103);
    assertThat(chunk.moreData()).isTrue();
    env.withProperty("daisy.jenkins.max-response-bytes", "2");
    assertThatThrownBy(() -> client().progressiveLog("folder/my job", 7, 100))
        .isInstanceOf(JenkinsClient.RequestException.class);
  }

  @Test
  void disabledAndUnknownJobFailWithoutNetwork() {
    assertThat(new JenkinsClient(new MockEnvironment(), new ObjectMapper()).enabled()).isFalse();
    assertThatThrownBy(() -> client().submit("unowned/job", "cmd-1", Map.of()))
        .isInstanceOf(com.teamdaisy.server.common.error.DaisyException.class);
    assertThatThrownBy(() -> client().build("folder/my job", 0))
        .isInstanceOf(com.teamdaisy.server.common.error.DaisyException.class);
  }
}
