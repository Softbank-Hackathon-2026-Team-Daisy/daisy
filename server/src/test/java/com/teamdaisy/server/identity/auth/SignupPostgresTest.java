package com.teamdaisy.server.identity.auth;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.teamdaisy.server.common.web.GlobalExceptionHandler;
import com.teamdaisy.server.identity.domain.AccountRepository;
import com.teamdaisy.server.identity.web.AuthController;
import com.teamdaisy.server.identity.web.BearerAuthFilter;
import com.teamdaisy.server.identity.web.CurrentAccountArgumentResolver;
import com.teamdaisy.server.project.domain.ProjectRepository;
import java.sql.Connection;
import java.sql.SQLException;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import javax.sql.DataSource;
import org.flywaydb.core.Flyway;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.condition.EnabledIfEnvironmentVariable;
import org.springframework.boot.WebApplicationType;
import org.springframework.boot.autoconfigure.EnableAutoConfiguration;
import org.springframework.boot.autoconfigure.domain.EntityScan;
import org.springframework.boot.builder.SpringApplicationBuilder;
import org.springframework.context.ConfigurableApplicationContext;
import org.springframework.context.annotation.Configuration;
import org.springframework.context.annotation.Import;
import org.springframework.context.support.StaticApplicationContext;
import org.springframework.data.jpa.repository.config.EnableJpaRepositories;
import org.springframework.http.MediaType;
import org.springframework.http.converter.json.MappingJackson2HttpMessageConverter;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.AbstractDataSource;
import org.springframework.jdbc.datasource.DriverManagerDataSource;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.ResultActions;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;
import org.springframework.web.servlet.mvc.method.annotation.ExceptionHandlerExceptionResolver;

/**
 * 회원가입(POST /auth/signup)을 실제 PostgreSQL·JPA·Bearer 필터로 HTTP 끝까지 확인해요.
 *
 * <p>테스트마다 새 schema 에 V1~V5 를 적용하고 끝나면 지워요.
 */
@EnabledIfEnvironmentVariable(named = "DAISY_TEST_DB_URL", matches = ".+")
class SignupPostgresTest {
  private static final String PASSWORD = "correct-horse-1";

  private final String schema = "daisy_su_" + UUID.randomUUID().toString().replace("-", "");
  private DataSource base;
  private DataSource scoped;
  private JdbcTemplate jdbc;
  private ConfigurableApplicationContext context;
  private MockMvc mvc;

  @BeforeEach
  void setup() {
    base =
        new DriverManagerDataSource(
            System.getenv("DAISY_TEST_DB_URL"),
            System.getenv("DAISY_TEST_DB_USER"),
            System.getenv("DAISY_TEST_DB_PASSWORD"));
    new JdbcTemplate(base).execute("CREATE SCHEMA " + schema);
    scoped =
        new AbstractDataSource() {
          @Override
          public Connection getConnection() throws SQLException {
            return scope(base.getConnection());
          }

          @Override
          public Connection getConnection(String user, String password) throws SQLException {
            return scope(base.getConnection(user, password));
          }

          private Connection scope(Connection connection) throws SQLException {
            connection.setSchema(schema);
            return connection;
          }
        };
    Flyway.configure()
        .dataSource(scoped)
        .defaultSchema(schema)
        .locations("classpath:db/migration")
        .load()
        .migrate();
    jdbc = new JdbcTemplate(scoped);
    jdbc.update(
        "insert into account(id,username,password_hash,display_name,role)"
            + " values('acct_seed','seed','TEST-ONLY-HASH','Seed','owner')");
  }

  @AfterEach
  void cleanup() {
    if (context != null) context.close();
    if (schema.matches("daisy_su_[a-f0-9]{32}"))
      new JdbcTemplate(base).execute("DROP SCHEMA IF EXISTS " + schema + " CASCADE");
  }

  /** 실제 서비스·리포지토리로 컨텍스트를 띄우고, 운영과 같은 Bearer 필터·오류 처리를 붙여요. */
  private void start(Map<String, String> extra) {
    // application.yml 이 기본 속성보다 앞서서, daisy.* 값은 명령행 인자로 넘겨요.
    Map<String, String> properties = new HashMap<>();
    properties.put("spring.flyway.enabled", "false");
    properties.put("spring.jpa.hibernate.ddl-auto", "validate");
    properties.put("spring.jpa.open-in-view", "false");
    properties.put("spring.jmx.enabled", "false");
    properties.put("daisy.auth.secret", "TEST-ONLY-signup-secret-0123456789abcdef");
    properties.putAll(extra);
    context =
        new SpringApplicationBuilder(TestConfig.class)
            .web(WebApplicationType.NONE)
            .initializers(
                application -> application.getBeanFactory().registerSingleton("dataSource", scoped))
            .run(
                properties.entrySet().stream()
                    .map(entry -> "--" + entry.getKey() + "=" + entry.getValue())
                    .toArray(String[]::new));
    // 운영과 같은 Jackson 설정(application.yml 의 SNAKE_CASE, ISO-8601 시각)을 써요.
    ObjectMapper mapper = context.getBean(ObjectMapper.class);
    var converter = new MappingJackson2HttpMessageConverter(mapper);
    var advice = new StaticApplicationContext();
    advice.registerSingleton("globalExceptionHandler", GlobalExceptionHandler.class);
    advice.refresh();
    var resolver = new ExceptionHandlerExceptionResolver();
    resolver.setApplicationContext(advice);
    resolver.setMessageConverters(List.of(converter));
    resolver.afterPropertiesSet();
    mvc =
        MockMvcBuilders.standaloneSetup(context.getBean(AuthController.class))
            .setControllerAdvice(new GlobalExceptionHandler())
            .setMessageConverters(converter)
            .setCustomArgumentResolvers(new CurrentAccountArgumentResolver())
            .addFilters(new BearerAuthFilter(context.getBean(AuthService.class), resolver))
            .build();
  }

  private void start() {
    start(Map.of());
  }

  private void project(String id, boolean archived) {
    jdbc.update(
        "insert into project(id,name,repository_id,repository_url,default_branch,created_by,archived_at)"
            + " values(?,?,?,'https://example.test/repo','main','acct_seed',"
            + (archived ? "now()" : "null")
            + ")",
        id,
        id,
        "repo-" + id);
  }

  private ResultActions signup(String body, String clientIp) throws Exception {
    return mvc.perform(
        post("/auth/signup")
            .header("X-Forwarded-For", clientIp + ", 10.0.0.1")
            .contentType(MediaType.APPLICATION_JSON)
            .content(body));
  }

  private static String body(String username, String password) {
    return "{\"username\":\"%s\",\"password\":\"%s\"}".formatted(username, password);
  }

  private long accounts() {
    return jdbc.queryForObject("select count(*) from account", Long.class);
  }

  @Test
  @DisplayName("가입하면 201 owner 토큰을 주고, 그 토큰으로 /auth/me 와 로그인이 돼요")
  void signupIssuesWorkingOwnerToken() throws Exception {
    project("prj_demo_monolith", false);
    start();

    String response =
        signup(
                """
                {"username":"  New.User ","password":"%s","display_name":"  새 사용자 "}"""
                    .formatted(PASSWORD),
                "203.0.113.1")
            .andExpect(status().isCreated())
            .andExpect(jsonPath("$.role").value("owner"))
            .andExpect(jsonPath("$.expires_at").value(org.hamcrest.Matchers.endsWith("Z")))
            .andReturn()
            .getResponse()
            .getContentAsString();
    String token = new ObjectMapper().readTree(response).get("access_token").asText();
    assertThat(token).isNotBlank();

    var row =
        jdbc.queryForMap(
            "select id,username,display_name,role,password_hash from account where username='new.user'");
    assertThat((String) row.get("id")).matches("acc_[0-9a-f]{32}");
    assertThat(row).containsEntry("display_name", "새 사용자").containsEntry("role", "owner");

    mvc.perform(get("/auth/me").header("Authorization", "Bearer " + token))
        .andExpect(status().isOk())
        .andExpect(jsonPath("$.account_id").value(row.get("id")))
        .andExpect(jsonPath("$.username").value("new.user"))
        .andExpect(jsonPath("$.role").value("owner"));
    mvc.perform(
            post("/auth/token")
                .contentType(MediaType.APPLICATION_JSON)
                .content(body("new.user", PASSWORD)))
        .andExpect(status().isOk())
        .andExpect(jsonPath("$.role").value("owner"));

    // 데모 프로젝트 멤버가 되고, 권한을 준 사람은 프로젝트를 만든 계정이에요.
    assertThat(
            jdbc.queryForList(
                "select project_id || ':' || granted_by from project_member"
                    + " where account_id=? and revoked_at is null",
                String.class,
                row.get("id")))
        .containsExactly("prj_demo_monolith:acct_seed");
  }

  @Test
  @DisplayName("비밀번호는 BCrypt 해시로만 저장해요")
  void passwordStoredHashed() throws Exception {
    start();
    signup(body("hashcheck", PASSWORD), "203.0.113.2").andExpect(status().isCreated());

    String hash =
        jdbc.queryForObject(
            "select password_hash from account where username='hashcheck'", String.class);
    assertThat(hash).isNotEqualTo(PASSWORD).doesNotContain(PASSWORD).startsWith("$2");
    assertThat(context.getBean(PasswordEncoder.class).matches(PASSWORD, hash)).isTrue();
  }

  @Test
  @DisplayName("없는·보관된 프로젝트는 건너뛰고, display_name 이 없으면 아이디를 써요")
  void skipsMissingAndArchivedProjects() throws Exception {
    project("prj_open", false);
    project("prj_archived", true);
    start(Map.of("daisy.signup.auto-join-projects", "prj_missing,prj_archived,prj_open"));

    signup(body("joiner", PASSWORD), "203.0.113.3").andExpect(status().isCreated());

    String id = jdbc.queryForObject("select id from account where username='joiner'", String.class);
    assertThat(jdbc.queryForObject("select display_name from account where id=?", String.class, id))
        .isEqualTo("joiner");
    assertThat(
            jdbc.queryForList(
                "select project_id from project_member where account_id=?", String.class, id))
        .containsExactly("prj_open");
  }

  @Test
  @DisplayName("기본 데모 프로젝트가 아직 없어도 가입은 돼요")
  void signupWithoutDemoProject() throws Exception {
    start();
    signup(body("lonely", PASSWORD), "203.0.113.4").andExpect(status().isCreated());
    assertThat(jdbc.queryForObject("select count(*) from project_member", Long.class)).isZero();
  }

  @Test
  @DisplayName("대소문자만 달라도 같은 아이디라 409 USERNAME_TAKEN 이에요")
  void duplicateUsernameIsCaseInsensitive() throws Exception {
    // 예전 방식으로 대문자가 섞여 저장된 계정도 막아요.
    jdbc.update(
        "insert into account(id,username,password_hash,display_name,role)"
            + " values('acct_legacy','Legacy','TEST-ONLY-HASH','Legacy','viewer')");
    start();

    signup(body("dup.user", PASSWORD), "203.0.113.5").andExpect(status().isCreated());
    signup(body(" DUP.User ", PASSWORD), "203.0.113.5")
        .andExpect(status().isConflict())
        .andExpect(jsonPath("$.error.code").value("USERNAME_TAKEN"));
    signup(body("legacy", PASSWORD), "203.0.113.5")
        .andExpect(status().isConflict())
        .andExpect(jsonPath("$.error.code").value("USERNAME_TAKEN"));
    assertThat(accounts()).isEqualTo(3);
  }

  @Test
  @DisplayName("V5 는 DB 에서도 대소문자만 다른 아이디를 막아요")
  void migrationBlocksCaseInsensitiveDuplicate() {
    org.assertj.core.api.Assertions.assertThatThrownBy(
            () ->
                jdbc.update(
                    "insert into account(id,username,password_hash,display_name,role)"
                        + " values('acct_x','SEED','TEST-ONLY-HASH','X','owner')"))
        .isInstanceOf(org.springframework.dao.DataIntegrityViolationException.class);
  }

  @Test
  @DisplayName("아이디·비밀번호·표시 이름이 규칙에 어긋나면 400 VALIDATION_FAILED 예요")
  void invalidInputIsRejected() throws Exception {
    start();
    List<String> bodies =
        List.of(
            body("ab", PASSWORD),
            body("-abc", PASSWORD),
            body("has space", PASSWORD),
            body("가나다라", PASSWORD),
            body("a".repeat(33), PASSWORD),
            body("a/b/c", PASSWORD),
            body("", PASSWORD),
            "{\"password\":\"" + PASSWORD + "\"}",
            body("okname", "short"),
            body("okname", " ".repeat(10)),
            body("okname", "p".repeat(201)),
            "{\"username\":\"okname\"}",
            """
            {"username":"okname","password":"%s","display_name":"%s"}"""
                .formatted(PASSWORD, "가".repeat(65)));
    for (int i = 0; i < bodies.size(); i++) {
      // 서비스 단계 검증 실패도 횟수에 들어가서 요청마다 IP 를 바꿔요.
      signup(bodies.get(i), "198.51.100." + i)
          .andExpect(status().isBadRequest())
          .andExpect(jsonPath("$.error.code").value("VALIDATION_FAILED"));
    }
    assertThat(accounts()).isEqualTo(1);

    // 경계값은 받아요: 3자·32자 아이디, 8자 비밀번호, 64자 표시 이름
    signup(body("a.b", "12345678"), "198.51.100.200").andExpect(status().isCreated());
    signup(
            """
            {"username":"%s","password":"%s","display_name":"%s"}"""
                .formatted("0" + "z".repeat(31), PASSWORD, "가".repeat(64)),
            "198.51.100.201")
        .andExpect(status().isCreated());
  }

  @Test
  @DisplayName("같은 IP 에서 10분에 5번을 넘으면 429 RATE_LIMITED 예요")
  void rateLimitedPerClientIp() throws Exception {
    start();
    for (int i = 0; i < SignupRateLimiter.LIMIT; i++) {
      signup(body("burst" + i, PASSWORD), "203.0.113.9").andExpect(status().isCreated());
    }
    signup(body("burst-extra", PASSWORD), "203.0.113.9")
        .andExpect(status().isTooManyRequests())
        .andExpect(jsonPath("$.error.code").value("RATE_LIMITED"))
        .andExpect(jsonPath("$.error.retryable").value(true));
    assertThat(
            jdbc.queryForObject(
                "select count(*) from account where username='burst-extra'", Long.class))
        .isZero();

    // 다른 IP 는 따로 세요. X-Forwarded-For 가 없으면 접속 주소로 세요.
    signup(body("other-ip", PASSWORD), "203.0.113.10").andExpect(status().isCreated());
    mvc.perform(
            post("/auth/signup")
                .with(
                    request -> {
                      request.setRemoteAddr("192.0.2.50");
                      return request;
                    })
                .contentType(MediaType.APPLICATION_JSON)
                .content(body("direct", PASSWORD)))
        .andExpect(status().isCreated());
  }

  @Test
  @DisplayName("회원가입을 끄면 403 FORBIDDEN 이고 계정을 만들지 않아요")
  void disabledSignupIsForbidden() throws Exception {
    start(Map.of("daisy.signup.enabled", "false"));
    signup(body("nobody", PASSWORD), "203.0.113.11")
        .andExpect(status().isForbidden())
        .andExpect(jsonPath("$.error.code").value("FORBIDDEN"));
    assertThat(accounts()).isEqualTo(1);
  }

  @Configuration(proxyBeanMethods = false)
  @EnableAutoConfiguration
  @EntityScan("com.teamdaisy.server")
  @EnableJpaRepositories(basePackageClasses = {AccountRepository.class, ProjectRepository.class})
  @Import({
    IdentityConfiguration.class,
    TokenService.class,
    AuthService.class,
    SignupRateLimiter.class,
    SignupService.class,
    AuthController.class
  })
  static class TestConfig {}
}
