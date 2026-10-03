package com.teamdaisy.server.push;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.teamdaisy.server.push.PushDeviceStore.Device;
import java.io.IOException;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.charset.StandardCharsets;
import java.time.Duration;

/**
 * JDK {@link HttpClient}(HTTP/2)로 APNs 에 보내요. 외부 라이브러리를 더하지 않으려고 직접 불러요.
 *
 * <p>기기 토큰은 APNs 경로에만 넣고 로그에는 끝 6자리만 남겨요.
 */
final class ApnsClient implements ApnsSender {
  static final String PRODUCTION = "https://api.push.apple.com";
  static final String SANDBOX = "https://api.sandbox.push.apple.com";
  private static final ObjectMapper JSON = new ObjectMapper();

  private final HttpClient http;
  private final ApnsJwt jwt;
  private final String topic;
  private final String production;
  private final String sandbox;

  ApnsClient(ApnsJwt jwt, String topic) {
    this(
        HttpClient.newBuilder()
            .version(HttpClient.Version.HTTP_2)
            .connectTimeout(Duration.ofSeconds(5))
            .build(),
        jwt,
        topic,
        PRODUCTION,
        SANDBOX);
  }

  /** 테스트에서 로컬 서버로 바꿔 끼울 수 있게 주소를 받아요. */
  ApnsClient(HttpClient http, ApnsJwt jwt, String topic, String production, String sandbox) {
    this.http = http;
    this.jwt = jwt;
    this.topic = topic;
    this.production = production;
    this.sandbox = sandbox;
  }

  @Override
  public boolean enabled() {
    return true;
  }

  @Override
  public Result send(Device device, String collapseId, String payloadJson) {
    String host = "sandbox".equals(device.apnsEnv()) ? sandbox : production;
    var request =
        HttpRequest.newBuilder(URI.create(host + "/3/device/" + device.apnsToken()))
            .timeout(Duration.ofSeconds(10))
            .header("authorization", "bearer " + jwt.current())
            .header("apns-topic", topic)
            .header("apns-push-type", "alert")
            .header("apns-priority", "10")
            .header("content-type", "application/json");
    // APNs 는 64바이트를 넘는 collapse id 를 거절해요. 넘으면 헤더 없이 보내요.
    if (collapseId != null && collapseId.getBytes(StandardCharsets.UTF_8).length <= 64)
      request.header("apns-collapse-id", collapseId);
    try {
      HttpResponse<String> response =
          http.send(
              request.POST(HttpRequest.BodyPublishers.ofString(payloadJson)).build(),
              HttpResponse.BodyHandlers.ofString());
      String reason = response.statusCode() == 200 ? null : reason(response.body());
      if (response.statusCode() == 403 && "ExpiredProviderToken".equals(reason)) jwt.invalidate();
      return new Result(response.statusCode(), reason);
    } catch (IOException e) {
      return new Result(0, e.getClass().getSimpleName());
    } catch (InterruptedException e) {
      Thread.currentThread().interrupt();
      return new Result(0, "Interrupted");
    }
  }

  static String reason(String body) {
    if (body == null || body.isBlank()) return null;
    try {
      var node = JSON.readTree(body).get("reason");
      return node == null || !node.isTextual() ? null : node.textValue();
    } catch (IOException e) {
      return null;
    }
  }
}
