package com.teamdaisy.server.identity.auth;

import com.teamdaisy.server.identity.domain.Account;
import com.teamdaisy.server.identity.domain.AccountRepository;
import java.time.Clock;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.ApplicationRunner;
import org.springframework.core.annotation.Order;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;

/**
 * 데모 계정을 심어요. 비밀번호는 환경변수로만 받고 해시만 저장해요.
 *
 * <p>환경변수가 없으면 아무것도 하지 않아요. 기본 비밀번호를 코드에 두지 않아요. 이미 있는 계정은 건드리지 않아요.
 */
@Component
@Order(50)
public class DemoAccountSeeder implements ApplicationRunner {
  private static final Logger LOG = LoggerFactory.getLogger(DemoAccountSeeder.class);

  private final AccountRepository accounts;
  private final org.springframework.security.crypto.password.PasswordEncoder passwordEncoder;
  private final Clock clock;
  private final String ownerUsername;
  private final String ownerPassword;
  private final String viewerUsername;
  private final String viewerPassword;

  public DemoAccountSeeder(
      AccountRepository accounts,
      org.springframework.security.crypto.password.PasswordEncoder passwordEncoder,
      Clock clock,
      @Value("${daisy.demo.owner-username:daisy}") String ownerUsername,
      @Value("${daisy.demo.owner-password:}") String ownerPassword,
      @Value("${daisy.demo.viewer-username:judge}") String viewerUsername,
      @Value("${daisy.demo.viewer-password:}") String viewerPassword) {
    this.accounts = accounts;
    this.passwordEncoder = passwordEncoder;
    this.clock = clock;
    this.ownerUsername = ownerUsername;
    this.ownerPassword = ownerPassword;
    this.viewerUsername = viewerUsername;
    this.viewerPassword = viewerPassword;
  }

  @Override
  @Transactional
  public void run(ApplicationArguments args) {
    seed("acc_demo_owner", ownerUsername, ownerPassword, "데모 운영자", "owner");
    seed("acc_demo_viewer", viewerUsername, viewerPassword, "읽기 전용", AuthPrincipal.VIEWER);
  }

  private void seed(
      String id, String username, String rawPassword, String displayName, String role) {
    if (rawPassword == null || rawPassword.isBlank()) {
      return;
    }
    if (accounts.findByUsername(username).isPresent()) {
      return;
    }
    accounts.save(
        Account.create(
            id, username, passwordEncoder.encode(rawPassword), displayName, role, clock.instant()));
    // 비밀번호는 로그에 남기지 않아요.
    LOG.info("데모 계정을 만들었어요. username={} role={}", username, role);
  }
}
