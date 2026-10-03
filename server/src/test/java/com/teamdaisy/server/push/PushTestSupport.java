package com.teamdaisy.server.push;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.PropertyNamingStrategies;
import com.teamdaisy.server.common.web.GlobalExceptionHandler;
import com.teamdaisy.server.identity.auth.AuthService;
import com.teamdaisy.server.identity.web.BearerAuthFilter;
import com.teamdaisy.server.identity.web.CurrentAccountArgumentResolver;
import java.sql.Connection;
import java.sql.SQLException;
import java.util.List;
import java.util.UUID;
import javax.sql.DataSource;
import org.flywaydb.core.Flyway;
import org.springframework.context.support.StaticApplicationContext;
import org.springframework.http.converter.json.Jackson2ObjectMapperBuilder;
import org.springframework.http.converter.json.MappingJackson2HttpMessageConverter;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.AbstractDataSource;
import org.springframework.jdbc.datasource.DriverManagerDataSource;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;
import org.springframework.web.servlet.mvc.method.annotation.ExceptionHandlerExceptionResolver;

/** 푸시 테스트가 같이 쓰는 준비물이에요. */
final class PushTestSupport {
  private PushTestSupport() {}

  /**
   * 실제 Bearer 필터·공통 오류 처리·주체 주입을 붙인 MockMvc 예요. 토큰 검증만 {@code auth} 목으로 바꿔요.
   *
   * <p>필터에서 난 인증 오류도 운영과 같은 {@link GlobalExceptionHandler} 로 응답해요.
   */
  static MockMvc mvc(PushDeviceStore store, AuthService auth) {
    ObjectMapper mapper =
        Jackson2ObjectMapperBuilder.json()
            .propertyNamingStrategy(PropertyNamingStrategies.SNAKE_CASE)
            .build();
    var converter = new MappingJackson2HttpMessageConverter(mapper);
    var context = new StaticApplicationContext();
    context.registerSingleton("globalExceptionHandler", GlobalExceptionHandler.class);
    context.refresh();
    var resolver = new ExceptionHandlerExceptionResolver();
    resolver.setApplicationContext(context);
    resolver.setMessageConverters(List.of(converter));
    resolver.afterPropertiesSet();
    return MockMvcBuilders.standaloneSetup(new PushDeviceController(new PushDeviceService(store)))
        .setControllerAdvice(new GlobalExceptionHandler())
        .setMessageConverters(converter)
        .setCustomArgumentResolvers(new CurrentAccountArgumentResolver())
        .addFilters(new BearerAuthFilter(auth, resolver))
        .build();
  }

  /** 테스트마다 새 schema 에 Flyway 전체를 적용한 테스트 DB 예요. 닫으면 그 schema 만 지워요. */
  static final class TestDatabase implements AutoCloseable {
    final String schema = "daisy_push_" + UUID.randomUUID().toString().replace("-", "");
    final DataSource base;
    final DataSource scoped;
    final JdbcTemplate jdbc;

    TestDatabase() {
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
    }

    void account(String id, String role) {
      jdbc.update(
          "insert into account(id,username,password_hash,display_name,role)"
              + " values(?,?,'TEST-ONLY-HASH','Fixture',?)",
          id,
          id,
          role);
    }

    @Override
    public void close() {
      if (schema.matches("daisy_push_[a-f0-9]{32}"))
        new JdbcTemplate(base).execute("DROP SCHEMA IF EXISTS " + schema + " CASCADE");
    }
  }
}
