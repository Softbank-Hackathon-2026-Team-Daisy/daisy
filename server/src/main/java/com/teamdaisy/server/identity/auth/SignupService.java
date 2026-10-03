package com.teamdaisy.server.identity.auth;

import com.teamdaisy.server.common.error.DaisyException;
import com.teamdaisy.server.common.error.ErrorCode;
import com.teamdaisy.server.identity.domain.Account;
import com.teamdaisy.server.identity.domain.AccountRepository;
import com.teamdaisy.server.project.domain.ProjectMember;
import com.teamdaisy.server.project.domain.ProjectMemberRepository;
import com.teamdaisy.server.project.domain.ProjectRepository;
import java.nio.charset.StandardCharsets;
import java.time.Clock;
import java.time.Instant;
import java.util.Locale;
import java.util.Map;
import java.util.UUID;
import java.util.regex.Pattern;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 회원가입이에요. 새 계정을 owner 로 만들고, 설정한 데모 프로젝트에 참여시킨 뒤 바로 토큰을 발급해요.
 *
 * <p>계정 저장과 프로젝트 참여는 한 트랜잭션이에요. 중간에 실패하면 계정도 남지 않아요.
 */
@Service
public class SignupService {
  private static final Logger LOG = LoggerFactory.getLogger(SignupService.class);
  private static final Pattern USERNAME = Pattern.compile("^[a-z0-9][a-z0-9._-]{2,31}$");
  private static final int DISPLAY_NAME_MAX = 64;

  /**
   * BCrypt 는 UTF-8 72바이트까지만 받아요. 넘으면 인코더가 IllegalArgumentException 을 던져서 500 이 돼요. 몰래 잘라 저장하지 않고
   * 400 으로 돌려요. 영문은 72자, 한글은 24자까지예요.
   */
  public static final int PASSWORD_MAX_BYTES = 72;

  private static final String ROLE = "owner";
  private static final String INVALID_FIELD = "값을 확인해 주세요.";

  private final AccountRepository accounts;
  private final ProjectRepository projects;
  private final ProjectMemberRepository members;
  private final PasswordEncoder passwordEncoder;
  private final TokenService tokens;
  private final SignupRateLimiter rateLimiter;
  private final SignupProperties properties;
  private final Clock clock;

  public SignupService(
      AccountRepository accounts,
      ProjectRepository projects,
      ProjectMemberRepository members,
      PasswordEncoder passwordEncoder,
      TokenService tokens,
      SignupRateLimiter rateLimiter,
      SignupProperties properties,
      Clock clock) {
    this.accounts = accounts;
    this.projects = projects;
    this.members = members;
    this.passwordEncoder = passwordEncoder;
    this.tokens = tokens;
    this.rateLimiter = rateLimiter;
    this.properties = properties;
    this.clock = clock;
  }

  /**
   * 계정을 만들고 토큰을 발급해요.
   *
   * <p>아이디는 앞뒤 공백을 지우고 소문자로 바꿔 저장해요. 로그인도 이 소문자 아이디로 해요. 꺼져 있으면 403, IP 별 시도가 넘치면 429, 대소문자만 다른
   * 아이디가 있으면 409 예요. 시도 횟수는 입력이 틀리거나 아이디가 겹친 요청도 세요. 아이디 존재 여부를 마구 떠보지 못하게 하려는 거예요.
   *
   * @param clientIp 횟수 제한 기준. 컨트롤러가 X-Forwarded-For 첫 값, 없으면 접속 주소로 넘겨요
   */
  @Transactional
  public AuthService.LoginResult signup(
      String username, String rawPassword, String displayName, String clientIp) {
    if (!properties.enabled()) {
      throw new DaisyException(ErrorCode.FORBIDDEN);
    }
    if (!rateLimiter.tryAcquire(clientIp)) {
      throw new DaisyException(ErrorCode.RATE_LIMITED);
    }
    String normalized = username == null ? "" : username.trim().toLowerCase(Locale.ROOT);
    if (!USERNAME.matcher(normalized).matches()) {
      throw invalid("username");
    }
    if (rawPassword == null
        || rawPassword.isBlank()
        || rawPassword.length() < 8
        || rawPassword.length() > 200
        || exceedsBcryptLimit(rawPassword)) {
      throw invalid("password");
    }
    String name = displayName == null ? "" : displayName.trim();
    if (name.length() > DISPLAY_NAME_MAX) {
      throw invalid("display_name");
    }
    if (name.isEmpty()) {
      name = normalized;
    }
    if (accounts.existsByUsernameIgnoreCase(normalized)) {
      throw new DaisyException(ErrorCode.USERNAME_TAKEN);
    }

    Instant now = clock.instant();
    String accountId = "acc_" + UUID.randomUUID().toString().replace("-", "");
    try {
      accounts.saveAndFlush(
          Account.create(
              accountId, normalized, passwordEncoder.encode(rawPassword), name, ROLE, now));
    } catch (DataIntegrityViolationException exception) {
      // 동시에 같은 아이디로 가입하면 존재 확인을 둘 다 통과할 수 있어요. 그때는 V5 소문자 UNIQUE 가 막아요.
      throw new DaisyException(ErrorCode.USERNAME_TAKEN);
    }
    for (String projectId : properties.autoJoinProjects()) {
      // 없는 프로젝트·보관된 프로젝트는 조용히 건너뛰어요. 데모 프로젝트가 아직 시딩되지 않은 환경도 있어서예요.
      projects
          .findById(projectId)
          .filter(project -> project.archivedAt() == null)
          .ifPresent(
              project ->
                  members.save(
                      ProjectMember.grant(project.id(), accountId, project.createdBy(), now)));
    }
    // 비밀번호는 로그에 남기지 않아요.
    LOG.info("회원가입으로 계정을 만들었어요. accountId={} username={}", accountId, normalized);
    TokenService.IssuedToken token = tokens.issue(accountId, normalized, now);
    return new AuthService.LoginResult(token.value(), token.expiresAt(), ROLE);
  }

  /** BCrypt 가 받을 수 없는 길이(UTF-8 72바이트 초과)인지 봐요. 로그인도 같은 기준을 써요. */
  public static boolean exceedsBcryptLimit(String rawPassword) {
    return rawPassword.getBytes(StandardCharsets.UTF_8).length > PASSWORD_MAX_BYTES;
  }

  private static DaisyException invalid(String field) {
    return new DaisyException(
        ErrorCode.VALIDATION_FAILED, Map.of("fields", Map.of(field, INVALID_FIELD)));
  }
}
