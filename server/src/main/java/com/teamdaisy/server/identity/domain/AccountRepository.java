package com.teamdaisy.server.identity.domain;

import java.util.Optional;
import org.springframework.data.jpa.repository.JpaRepository;

public interface AccountRepository extends JpaRepository<Account, String> {
  Optional<Account> findByUsername(String username);

  /** 대소문자만 다른 아이디도 같은 아이디로 봐요 (V5 ux_account_username_lower). */
  boolean existsByUsernameIgnoreCase(String username);
}
