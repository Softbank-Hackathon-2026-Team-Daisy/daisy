package com.teamdaisy.server.push;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.doReturn;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.teamdaisy.server.common.error.DaisyException;
import com.teamdaisy.server.common.error.ErrorCode;
import com.teamdaisy.server.identity.auth.AuthPrincipal;
import com.teamdaisy.server.identity.auth.AuthService;
import java.util.Map;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.condition.EnabledIfEnvironmentVariable;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.http.MediaType;
import org.springframework.jdbc.core.namedparam.NamedParameterJdbcTemplate;
import org.springframework.test.web.servlet.MockMvc;

/**
 * V4 마이그레이션과 기기 저장을 실제 PostgreSQL 에서 HTTP 로 확인해요.
 *
 * <p>테스트마다 새 schema 에 V1~V4 를 적용하고 끝나면 지워요.
 */
@EnabledIfEnvironmentVariable(named = "DAISY_TEST_DB_URL", matches = ".+")
class PushDevicePostgresTest {
  private static final String TOKEN = "0a1b2c3d4e5f".repeat(6);

  private PushTestSupport.TestDatabase db;
  private PushDeviceStore store;
  private MockMvc mvc;

  @BeforeEach
  void setup() {
    db = new PushTestSupport.TestDatabase();
    db.account("acct_a", "owner");
    db.account("acct_b", "viewer");
    store = new PushDeviceStore(new NamedParameterJdbcTemplate(db.scoped));
    AuthService auth = mock(AuthService.class);
    when(auth.resolve(anyString())).thenThrow(new DaisyException(ErrorCode.UNAUTHENTICATED));
    doReturn(new AuthPrincipal("acct_a", "acct_a", "owner")).when(auth).resolve("token-a");
    doReturn(new AuthPrincipal("acct_b", "acct_b", "viewer")).when(auth).resolve("token-b");
    mvc = PushTestSupport.mvc(store, auth);
  }

  @AfterEach
  void cleanup() {
    if (db != null) db.close();
  }

  private void register(String bearer, String token, String platform, String env) throws Exception {
    mvc.perform(
            post("/devices")
                .header("Authorization", "Bearer " + bearer)
                .contentType(MediaType.APPLICATION_JSON)
                .content(
                    """
                    {"apns_token":"%s","platform":"%s","apns_env":"%s"}"""
                        .formatted(token, platform, env)))
        .andExpect(status().isNoContent());
  }

  private void unregister(String bearer, String token) throws Exception {
    mvc.perform(
            delete("/devices")
                .header("Authorization", "Bearer " + bearer)
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"apns_token\":\"" + token + "\"}"))
        .andExpect(status().isNoContent());
  }

  private Map<String, Object> row(String token) {
    return db.jdbc.queryForMap(
        "select account_id,platform,apns_env,disabled_at,last_error from push_device where apns_token=?",
        token);
  }

  private long count() {
    return db.jdbc.queryForObject("select count(*) from push_device", Long.class);
  }

  @Test
  @DisplayName("등록하면 204 로 저장되고, 같은 토큰 재등록은 지금 계정으로 옮기며 다시 켜요")
  void registerAndReRegisterMovesOwner() throws Exception {
    register("token-a", TOKEN, "ios", "production");
    assertThat(row(TOKEN))
        .containsEntry("account_id", "acct_a")
        .containsEntry("platform", "ios")
        .containsEntry("apns_env", "production");

    // APNs 가 거절해 꺼진 토큰이라도 다시 등록하면 살아나요.
    store.disable(TOKEN, "Unregistered");
    assertThat(row(TOKEN).get("disabled_at")).isNotNull();

    register("token-b", TOKEN.toUpperCase(), "macos", "sandbox");
    assertThat(count()).isEqualTo(1);
    assertThat(row(TOKEN))
        .containsEntry("account_id", "acct_b")
        .containsEntry("platform", "macos")
        .containsEntry("apns_env", "sandbox")
        .containsEntry("disabled_at", null)
        .containsEntry("last_error", null);
  }

  @Test
  @DisplayName("해제는 내 토큰만 지우고, 남의 토큰·모르는 토큰은 204 로 그대로 둬요")
  void deleteOnlyOwnToken() throws Exception {
    String other = "f".repeat(64);
    register("token-a", TOKEN, "ios", "production");
    register("token-b", other, "ios", "sandbox");

    unregister("token-a", other);
    unregister("token-a", "9".repeat(64));
    assertThat(count()).isEqualTo(2);
    assertThat(row(other)).containsEntry("account_id", "acct_b");

    unregister("token-a", TOKEN);
    assertThat(count()).isEqualTo(1);
    assertThat(db.jdbc.queryForList("select apns_token from push_device", String.class))
        .containsExactly(other);
    // 같은 해제를 다시 보내도 204 예요.
    unregister("token-a", TOKEN);
  }

  @Test
  @DisplayName("DB 제약이 API 검증과 같은 값만 받아요")
  void migrationConstraints() {
    assertThatThrownBy(
            () ->
                db.jdbc.update(
                    "insert into push_device(apns_token,account_id,platform,apns_env)"
                        + " values(?, 'acct_a','android','production')",
                    TOKEN))
        .isInstanceOf(DataIntegrityViolationException.class);
    assertThatThrownBy(
            () ->
                db.jdbc.update(
                    "insert into push_device(apns_token,account_id,platform,apns_env)"
                        + " values(?, 'acct_a','ios','development')",
                    TOKEN))
        .isInstanceOf(DataIntegrityViolationException.class);
    assertThatThrownBy(
            () ->
                db.jdbc.update(
                    "insert into push_device(apns_token,account_id,platform,apns_env)"
                        + " values(?, 'acct_a','ios','production')",
                    TOKEN.toUpperCase()))
        .isInstanceOf(DataIntegrityViolationException.class);
    assertThatThrownBy(
            () ->
                db.jdbc.update(
                    "insert into push_device(apns_token,account_id,platform,apns_env)"
                        + " values(?, 'acct_missing','ios','production')",
                    TOKEN))
        .isInstanceOf(DataIntegrityViolationException.class);
    assertThatThrownBy(() -> db.jdbc.update("insert into push_cursor(name,last_id) values('x',-1)"))
        .isInstanceOf(DataIntegrityViolationException.class);
    assertThat(
            db.jdbc.queryForObject(
                "select version from flyway_schema_history where script='V4__push_devices.sql' and success",
                String.class))
        .isEqualTo("4");
  }
}
