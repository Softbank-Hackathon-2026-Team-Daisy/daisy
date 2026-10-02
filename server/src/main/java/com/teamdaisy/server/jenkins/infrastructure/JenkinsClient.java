package com.teamdaisy.server.jenkins.infrastructure;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.teamdaisy.server.common.error.DaisyException;
import com.teamdaisy.server.common.error.ErrorCode;
import java.io.ByteArrayOutputStream;
import java.net.URI;
import java.net.URLEncoder;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.ByteBuffer;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.util.Arrays;
import java.util.Base64;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.CompletionStage;
import java.util.concurrent.Flow;
import java.util.concurrent.TimeUnit;
import org.springframework.core.env.Environment;
import org.springframework.stereotype.Component;

/** Jenkins transport only: acknowledgements and build results are not deployment results. */
@Component
public class JenkinsClient {
  private final ObjectMapper mapper;
  private final boolean enabled;
  private final URI base;
  private final Set<String> jobs;
  private final String authorization;
  private final Duration timeout;
  private final int maxBytes;
  private final HttpClient http;

  public JenkinsClient(Environment env, ObjectMapper mapper) {
    this.mapper = mapper;
    enabled = env.getProperty("daisy.jenkins.enabled", Boolean.class, false);
    if (!enabled) {
      base = null;
      jobs = Set.of();
      authorization = null;
      timeout = Duration.ofSeconds(15);
      maxBytes = 262144;
      http = null;
      return;
    }
    try {
      String origin = env.getRequiredProperty("daisy.jenkins.base-url");
      base = URI.create(origin.endsWith("/") ? origin : origin + "/");
      if (!(base.getScheme().equals("https") || base.getScheme().equals("http"))
          || base.getHost() == null
          || base.getRawUserInfo() != null
          || base.getRawQuery() != null
          || base.getRawFragment() != null
          || !base.getRawPath().equals(base.normalize().getRawPath())
          || base.getRawPath().contains("%")) throw new IllegalArgumentException();
      jobs =
          Set.copyOf(
              Arrays.stream(env.getRequiredProperty("daisy.jenkins.jobs").split(","))
                  .map(String::trim)
                  .toList());
      jobs.forEach(this::job);
      String user = env.getRequiredProperty("daisy.jenkins.user");
      String token = env.getRequiredProperty("daisy.jenkins.token");
      if (user.isBlank() || user.contains(":") || token.isBlank())
        throw new IllegalArgumentException();
      authorization =
          "Basic "
              + Base64.getEncoder()
                  .encodeToString((user + ":" + token).getBytes(StandardCharsets.UTF_8));
      long connect = env.getProperty("daisy.jenkins.connect-timeout-ms", Long.class, 3000L);
      long read = env.getProperty("daisy.jenkins.read-timeout-ms", Long.class, 15000L);
      maxBytes = env.getProperty("daisy.jenkins.max-response-bytes", Integer.class, 262144);
      if (connect <= 0 || read <= 0 || maxBytes <= 0 || maxBytes > 1048576)
        throw new IllegalArgumentException();
      timeout = Duration.ofMillis(read);
      http =
          HttpClient.newBuilder()
              .connectTimeout(Duration.ofMillis(connect))
              .followRedirects(HttpClient.Redirect.NEVER)
              .build();
    } catch (Exception e) {
      throw new RequestException(true);
    }
  }

  public boolean enabled() {
    return enabled;
  }

  public Submission submit(String jobPath, String requestId, Map<String, Object> payload) {
    validateRequestId(requestId);
    String json;
    try {
      Map<String, Object> command = new LinkedHashMap<>(payload);
      command.put("request_id", requestId);
      json = mapper.writeValueAsString(command);
    } catch (Exception e) {
      throw new RequestException(true);
    }
    if (json.getBytes(StandardCharsets.UTF_8).length > maxBytes) throw new RequestException(true);
    HttpResponse<byte[]> response =
        request(
            "POST",
            job(jobPath) + "buildWithParameters",
            "request_id=" + encode(requestId) + "&payload=" + encode(json));
    if (response.statusCode() != 201) throw new RequestException(false);
    try {
      URI location = base.resolve(response.headers().firstValue("Location").orElseThrow());
      String prefix = base.getRawPath() + "queue/item/";
      if (!sameOrigin(location)
          || location.getRawUserInfo() != null
          || location.getRawQuery() != null
          || location.getRawFragment() != null
          || !location.getRawPath().matches(java.util.regex.Pattern.quote(prefix) + "[1-9][0-9]*/"))
        throw new IllegalArgumentException();
      return new Submission(
          positive(
              Long.parseLong(
                  location
                      .getRawPath()
                      .substring(prefix.length(), location.getRawPath().length() - 1))));
    } catch (Exception e) {
      throw new RequestException(false);
    }
  }

  public QueueSnapshot queue(String jobPath, long queueId) {
    String expectedJob = job(jobPath);
    JsonNode node = json(request("GET", "queue/item/" + positive(queueId) + "/api/json", null));
    Long number =
        node.path("executable").has("number")
            ? positive(node.path("executable").path("number").asLong())
            : null;
    if (number != null
        && !base.resolve(expectedJob + number + "/")
            .toString()
            .equals(node.path("executable").path("url").asText()))
      throw new RequestException(false);
    if (node.path("task").has("url")
        && !base.resolve(expectedJob).toString().equals(node.path("task").path("url").asText()))
      throw new RequestException(false);
    return new QueueSnapshot(node.path("cancelled").asBoolean(), number);
  }

  public BuildSnapshot build(String jobPath, long buildNumber) {
    JsonNode node = json(request("GET", job(jobPath) + positive(buildNumber) + "/api/json", null));
    if (!node.path("building").isBoolean()) throw new RequestException(false);
    return new BuildSnapshot(
        node.path("building").asBoolean(),
        node.path("result").isTextual() ? node.path("result").asText() : null);
  }

  public void cancelQueue(long queueId) {
    request("POST", "queue/cancelItem", "id=" + positive(queueId));
  }

  public void stopBuild(String jobPath, long buildNumber) {
    request("POST", job(jobPath) + positive(buildNumber) + "/stop", "");
  }

  public LogChunk progressiveLog(String jobPath, long buildNumber, long start) {
    if (start < 0) throw new DaisyException(ErrorCode.VALIDATION_FAILED);
    HttpResponse<byte[]> response =
        request(
            "GET",
            job(jobPath) + positive(buildNumber) + "/logText/progressiveText?start=" + start,
            null);
    try {
      long next = Long.parseLong(response.headers().firstValue("X-Text-Size").orElseThrow());
      if (next < start) throw new IllegalArgumentException();
      String more = response.headers().firstValue("X-More-Data").orElse("false");
      if (!more.equals("true") && !more.equals("false")) throw new IllegalArgumentException();
      return new LogChunk(response.body(), next, Boolean.parseBoolean(more));
    } catch (Exception e) {
      throw new RequestException(false);
    }
  }

  /** Bounded observation only; UNKNOWN never authorizes resubmission. */
  public RequestLookup findRequest(String jobPath, String requestId) {
    validateRequestId(requestId);
    String expectedJob = job(jobPath);
    Map<Long, Long> matches = new LinkedHashMap<>();
    JsonNode queue =
        json(
            request(
                "GET",
                "queue/api/json?tree="
                    + encode("items[id,task[url],actions[parameters[name,value]]]"),
                null));
    for (JsonNode item : queue.path("items")) {
      if (base.resolve(expectedJob).toString().equals(item.path("task").path("url").asText())
          && hasRequest(item, requestId)) matches.put(positive(item.path("id").asLong()), null);
    }
    JsonNode builds =
        json(
            request(
                "GET",
                expectedJob
                    + "api/json?tree="
                    + encode("builds[number,queueId,actions[parameters[name,value]]]{0,100}"),
                null));
    for (JsonNode item : builds.path("builds")) {
      if (hasRequest(item, requestId))
        matches.put(
            positive(item.path("queueId").asLong()), positive(item.path("number").asLong()));
    }
    if (matches.size() != 1)
      return new RequestLookup(
          matches.isEmpty() ? LookupState.UNKNOWN : LookupState.AMBIGUOUS, null, null);
    var match = matches.entrySet().iterator().next();
    return new RequestLookup(LookupState.FOUND, match.getKey(), match.getValue());
  }

  private boolean hasRequest(JsonNode item, String id) {
    for (JsonNode action : item.path("actions"))
      for (JsonNode parameter : action.path("parameters"))
        if (parameter.path("name").asText().equals("request_id")
            && parameter.path("value").asText().equals(id)) return true;
    return false;
  }

  private HttpResponse<byte[]> request(String method, String path, String body) {
    if (!enabled) throw new RequestException(true);
    CompletableFuture<HttpResponse<byte[]>> future;
    try {
      HttpRequest.Builder builder =
          HttpRequest.newBuilder(base.resolve(path))
              .timeout(timeout)
              .header("Authorization", authorization)
              .header("Accept", "application/json");
      if (body == null) builder.GET();
      else
        builder
            .header("Content-Type", "application/x-www-form-urlencoded; charset=UTF-8")
            .method(method, HttpRequest.BodyPublishers.ofString(body));
      future = http.sendAsync(builder.build(), ignored -> new LimitedBody(maxBytes));
    } catch (Exception e) {
      throw new RequestException(false);
    }
    try {
      HttpResponse<byte[]> response = future.get(timeout.toMillis(), TimeUnit.MILLISECONDS);
      int status = response.statusCode();
      if (status < 200 || status >= 300)
        throw new RequestException(status == 401 || status == 403 || status == 404);
      return response;
    } catch (RequestException e) {
      throw e;
    } catch (Exception e) {
      future.cancel(true);
      if (e instanceof InterruptedException) Thread.currentThread().interrupt();
      throw new RequestException(false);
    }
  }

  private JsonNode json(HttpResponse<byte[]> response) {
    try {
      return mapper.readTree(response.body());
    } catch (Exception e) {
      throw new RequestException(false);
    }
  }

  private String job(String jobPath) {
    if (jobPath == null || !jobs.contains(jobPath))
      throw new DaisyException(ErrorCode.VALIDATION_FAILED);
    StringBuilder path = new StringBuilder();
    for (String segment : jobPath.split("/", -1)) {
      if (segment.isBlank()
          || segment.equals(".")
          || segment.equals("..")
          || segment.chars().anyMatch(c -> c < 32 || c == 127))
        throw new DaisyException(ErrorCode.VALIDATION_FAILED);
      path.append("job/").append(encode(segment).replace("+", "%20")).append('/');
    }
    return path.toString();
  }

  private boolean sameOrigin(URI uri) {
    return base.getScheme().equalsIgnoreCase(uri.getScheme())
        && base.getHost().equalsIgnoreCase(uri.getHost())
        && port(base) == port(uri);
  }

  private static int port(URI uri) {
    return uri.getPort() >= 0
        ? uri.getPort()
        : ("https".equalsIgnoreCase(uri.getScheme()) ? 443 : 80);
  }

  private static String encode(String value) {
    return URLEncoder.encode(value, StandardCharsets.UTF_8);
  }

  private static long positive(long value) {
    if (value <= 0) throw new DaisyException(ErrorCode.VALIDATION_FAILED);
    return value;
  }

  private static void validateRequestId(String id) {
    if (id == null || !id.matches("[A-Za-z0-9._-]{1,128}"))
      throw new DaisyException(ErrorCode.VALIDATION_FAILED);
  }

  public record Submission(long queueId) {}

  public record QueueSnapshot(boolean cancelled, Long buildNumber) {}

  public record BuildSnapshot(boolean building, String result) {}

  public record LogChunk(byte[] bytes, long nextOffset, boolean moreData) {}

  public enum LookupState {
    FOUND,
    UNKNOWN,
    AMBIGUOUS
  }

  public record RequestLookup(LookupState state, Long queueId, Long buildNumber) {}

  /** Rejection only means this HTTP request was denied, never proof about an earlier request. */
  public static final class RequestException extends DaisyException {
    private final boolean definitelyRejected;

    public RequestException(boolean definitelyRejected) {
      super(ErrorCode.INTERNAL);
      this.definitelyRejected = definitelyRejected;
    }

    public boolean definitelyRejected() {
      return definitelyRejected;
    }
  }

  private static final class LimitedBody implements HttpResponse.BodySubscriber<byte[]> {
    private final CompletableFuture<byte[]> result = new CompletableFuture<>();
    private final ByteArrayOutputStream bytes = new ByteArrayOutputStream();
    private final int limit;
    private Flow.Subscription subscription;

    LimitedBody(int limit) {
      this.limit = limit;
    }

    public CompletionStage<byte[]> getBody() {
      return result;
    }

    public void onSubscribe(Flow.Subscription value) {
      subscription = value;
      value.request(1);
    }

    public void onNext(List<ByteBuffer> buffers) {
      for (ByteBuffer buffer : buffers) {
        if (buffer.remaining() > limit - bytes.size()) {
          subscription.cancel();
          result.completeExceptionally(new RequestException(false));
          return;
        }
        byte[] chunk = new byte[buffer.remaining()];
        buffer.get(chunk);
        bytes.writeBytes(chunk);
      }
      subscription.request(1);
    }

    public void onError(Throwable error) {
      result.completeExceptionally(new RequestException(false));
    }

    public void onComplete() {
      result.complete(bytes.toByteArray());
    }
  }
}
