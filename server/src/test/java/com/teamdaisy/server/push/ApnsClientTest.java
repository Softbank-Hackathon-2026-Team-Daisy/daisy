package com.teamdaisy.server.push;

import static org.assertj.core.api.Assertions.assertThat;

import com.sun.net.httpserver.HttpServer;
import com.teamdaisy.server.push.PushDeviceStore.Device;
import java.net.InetSocketAddress;
import java.net.http.HttpClient;
import java.nio.charset.StandardCharsets;
import java.security.KeyPairGenerator;
import java.security.spec.ECGenParameterSpec;
import java.time.Clock;
import java.util.List;
import java.util.Map;
import java.util.concurrent.CopyOnWriteArrayList;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

/** APNs 요청 모양(경로·헤더·본문)과 응답 해석을 로컬 HTTP 서버로 확인해요. 실제 Apple 서버는 부르지 않아요. */
class ApnsClientTest {
  private record Seen(String host, String path, Map<String, List<String>> headers, String body) {}

  private HttpServer server;
  private final List<Seen> seen = new CopyOnWriteArrayList<>();
  private ApnsClient client;

  @BeforeEach
  void setup() throws Exception {
    server = HttpServer.create(new InetSocketAddress("127.0.0.1", 0), 0);
    for (String host : List.of("/prod", "/sandbox")) {
      server.createContext(
          host,
          exchange -> {
            String path = exchange.getRequestURI().getPath();
            seen.add(
                new Seen(
                    host,
                    path.substring(host.length()),
                    Map.copyOf(exchange.getRequestHeaders()),
                    new String(exchange.getRequestBody().readAllBytes(), StandardCharsets.UTF_8)));
            boolean bad = path.endsWith("b".repeat(64));
            byte[] body =
                bad
                    ? "{\"reason\":\"BadDeviceToken\"}".getBytes(StandardCharsets.UTF_8)
                    : new byte[0];
            exchange.sendResponseHeaders(bad ? 400 : 200, bad ? body.length : -1);
            exchange.getResponseBody().write(body);
            exchange.close();
          });
    }
    server.start();
    var generator = KeyPairGenerator.getInstance("EC");
    generator.initialize(new ECGenParameterSpec("secp256r1"));
    var jwt =
        new ApnsJwt(generator.generateKeyPair().getPrivate(), "KEY", "TEAM", Clock.systemUTC());
    String base = "http://127.0.0.1:" + server.getAddress().getPort();
    client =
        new ApnsClient(
            HttpClient.newHttpClient(),
            jwt,
            "com.teamdaisy.daisy",
            base + "/prod",
            base + "/sandbox");
  }

  @AfterEach
  void cleanup() {
    server.stop(0);
  }

  @Test
  @DisplayName("환경별 주소로 APNs 헤더와 본문을 보내고 200 을 성공으로 읽어요")
  void sendsAlertWithApnsHeaders() {
    String token = "a".repeat(64);
    var result =
        client.send(
            new Device(token, "acct", "ios", "production"), "approval-dep_1", "{\"aps\":{}}");

    assertThat(result.ok()).isTrue();
    Seen request = seen.getFirst();
    assertThat(request.host()).isEqualTo("/prod");
    assertThat(request.path()).isEqualTo("/3/device/" + token);
    assertThat(request.body()).isEqualTo("{\"aps\":{}}");
    assertThat(request.headers().get("Authorization").getFirst()).startsWith("bearer ey");
    assertThat(request.headers().get("Apns-topic")).containsExactly("com.teamdaisy.daisy");
    assertThat(request.headers().get("Apns-push-type")).containsExactly("alert");
    assertThat(request.headers().get("Apns-priority")).containsExactly("10");
    assertThat(request.headers().get("Apns-collapse-id")).containsExactly("approval-dep_1");

    client.send(new Device(token, "acct", "macos", "sandbox"), "x".repeat(65), "{}");
    assertThat(seen.get(1).host()).isEqualTo("/sandbox");
    // 64바이트를 넘는 collapse id 는 APNs 가 거절해서 빼고 보내요.
    assertThat(seen.get(1).headers()).doesNotContainKey("Apns-collapse-id");
  }

  @Test
  @DisplayName("400 BadDeviceToken 은 기기를 끌 응답이고, 연결 실패는 예외 없이 결과로 돌려줘요")
  void readsFailures() {
    var rejected =
        client.send(new Device("b".repeat(64), "acct", "ios", "production"), "result-dep", "{}");
    assertThat(rejected.status()).isEqualTo(400);
    assertThat(rejected.reason()).isEqualTo("BadDeviceToken");
    assertThat(rejected.deviceGone()).isTrue();

    server.stop(0);
    var unreachable =
        client.send(new Device("c".repeat(64), "acct", "ios", "production"), "result-dep", "{}");
    assertThat(unreachable.status()).isZero();
    assertThat(unreachable.ok()).isFalse();
    assertThat(unreachable.deviceGone()).isFalse();
  }
}
