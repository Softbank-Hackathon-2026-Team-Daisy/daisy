package com.teamdaisy.server.identity.auth;

import java.util.List;
import org.springframework.boot.context.properties.ConfigurationProperties;

/**
 * 회원가입 설정이에요. 비밀값은 없어요.
 *
 * @param enabled 회원가입을 받을지. 끄면 403 이에요 (기본 true)
 * @param autoJoinProjects 새 계정을 바로 참여시킬 프로젝트 ID 목록 (기본 prj_demo_monolith)
 */
@ConfigurationProperties(prefix = "daisy.signup")
public record SignupProperties(Boolean enabled, List<String> autoJoinProjects) {
  public SignupProperties {
    enabled = enabled == null || enabled;
    autoJoinProjects =
        autoJoinProjects == null
            ? List.of("prj_demo_monolith")
            : autoJoinProjects.stream()
                .filter(id -> id != null && !id.isBlank())
                .map(String::trim)
                .distinct()
                .toList();
  }
}
