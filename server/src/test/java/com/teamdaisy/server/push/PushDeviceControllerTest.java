package com.teamdaisy.server.push;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.doReturn;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.teamdaisy.server.common.error.DaisyException;
import com.teamdaisy.server.common.error.ErrorCode;
import com.teamdaisy.server.identity.auth.AuthPrincipal;
import com.teamdaisy.server.identity.auth.AuthService;
import java.util.stream.Stream;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.MethodSource;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.request.MockHttpServletRequestBuilder;

/**
 * {@code POST·DELETE /devices} 의 입력 검증·인증을 DB 없이 봐요. 저장 동작은 {@link PushDevicePostgresTest} 에서 봐요.
 */
class PushDeviceControllerTest {
  private static final String TOKEN = "AB".repeat(32);

  private PushDeviceStore store;
  private MockMvc mvc;

  @BeforeEach
  void setup() {
    store = mock(PushDeviceStore.class);
    AuthService auth = mock(AuthService.class);
    when(auth.resolve(anyString())).thenThrow(new DaisyException(ErrorCode.UNAUTHENTICATED));
    doReturn(new AuthPrincipal("acct_viewer", "judge", AuthPrincipal.VIEWER))
        .when(auth)
        .resolve("viewer-token");
    mvc = PushTestSupport.mvc(store, auth);
  }

  private static MockHttpServletRequestBuilder json(
      MockHttpServletRequestBuilder request, String body) {
    return request
        .header("Authorization", "Bearer viewer-token")
        .contentType(MediaType.APPLICATION_JSON)
        .content(body);
  }

  private static String register(String token, String platform, String env) {
    return """
        {"apns_token":"%s","platform":"%s","apns_env":"%s"}"""
        .formatted(token, platform, env);
  }

  @Test
  @DisplayName("읽기 전용 계정도 등록할 수 있고 토큰은 소문자로 저장해요")
  void viewerCanRegister() throws Exception {
    mvc.perform(json(post("/devices"), register(TOKEN, "macos", "sandbox")))
        .andExpect(status().isNoContent());
    verify(store).upsert("acct_viewer", TOKEN.toLowerCase(), "macos", "sandbox");
  }

  static Stream<String> invalidTokens() {
    return Stream.of(
        "", // 비어 있음
        "a".repeat(31), // 32자보다 짧음
        "z".repeat(64), // 16진수가 아님
        "a".repeat(201), // 200자보다 김
        "ab cd".repeat(10)); // 공백 포함
  }

  @ParameterizedTest
  @MethodSource("invalidTokens")
  @DisplayName("토큰이 16진수 32~200자가 아니면 400 VALIDATION_FAILED")
  void rejectsInvalidToken(String token) throws Exception {
    mvc.perform(json(post("/devices"), register(token, "ios", "production")))
        .andExpect(status().isBadRequest())
        .andExpect(jsonPath("$.error.code").value("VALIDATION_FAILED"));
    mvc.perform(json(delete("/devices"), "{\"apns_token\":\"" + token + "\"}"))
        .andExpect(status().isBadRequest())
        .andExpect(jsonPath("$.error.code").value("VALIDATION_FAILED"));
    verifyNoInteractions(store);
  }

  @Test
  @DisplayName("platform·apns_env 가 약속한 값이 아니거나 본문이 없으면 400")
  void rejectsInvalidEnumsAndBody() throws Exception {
    for (String body :
        new String[] {
          register(TOKEN, "android", "production"),
          register(TOKEN, "iOS", "production"),
          register(TOKEN, "ios", "development"),
          "{\"apns_token\":\"" + TOKEN + "\",\"platform\":\"ios\"}",
          "{}",
          "not-json"
        }) {
      mvc.perform(json(post("/devices"), body))
          .andExpect(status().isBadRequest())
          .andExpect(jsonPath("$.error.code").value("VALIDATION_FAILED"));
    }
    mvc.perform(
            post("/devices")
                .header("Authorization", "Bearer viewer-token")
                .contentType(MediaType.APPLICATION_JSON))
        .andExpect(status().isBadRequest());
    verifyNoInteractions(store);
  }

  @Test
  @DisplayName("Bearer 토큰이 없거나 틀리면 401 이고 저장하지 않아요")
  void requiresAuthentication() throws Exception {
    mvc.perform(
            post("/devices")
                .contentType(MediaType.APPLICATION_JSON)
                .content(register(TOKEN, "ios", "production")))
        .andExpect(status().isUnauthorized())
        .andExpect(jsonPath("$.error.code").value("UNAUTHENTICATED"));
    mvc.perform(
            delete("/devices")
                .header("Authorization", "Bearer wrong")
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"apns_token\":\"" + TOKEN + "\"}"))
        .andExpect(status().isUnauthorized());
    verifyNoInteractions(store);
  }

  @Test
  @DisplayName("해제는 호출한 계정 기준으로 넘겨요")
  void unregisterUsesCaller() throws Exception {
    mvc.perform(json(delete("/devices"), "{\"apns_token\":\"" + TOKEN + "\"}"))
        .andExpect(status().isNoContent());
    verify(store).delete("acct_viewer", TOKEN.toLowerCase());
    verify(store, org.mockito.Mockito.never()).upsert(any(), any(), any(), any());
  }
}
