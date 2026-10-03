package com.teamdaisy.server.identity.web;

import com.teamdaisy.server.identity.auth.AuthPrincipal;
import com.teamdaisy.server.identity.auth.AuthService;
import com.teamdaisy.server.identity.auth.SignupService;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.responses.ApiResponse;
import io.swagger.v3.oas.annotations.security.SecurityRequirement;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;
import java.time.Instant;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

/** 로그인·회원가입과 내 정보 조회예요. */
@RestController
public class AuthController {
  private final AuthService authService;
  private final SignupService signupService;

  public AuthController(AuthService authService, SignupService signupService) {
    this.authService = authService;
    this.signupService = signupService;
  }

  @PostMapping("/auth/token")
  @Operation(
      summary = "계정 로그인",
      description =
          "준비된 데모 계정이나 POST /auth/signup 으로 만든 계정의 토큰을 발급해요. 토큰은 REST·SSE의 Authorization: Bearer 헤더에 전달해요.")
  public TokenResponse issueToken(@Valid @RequestBody LoginRequest request) {
    AuthService.LoginResult result = authService.login(request.username(), request.password());
    return new TokenResponse(result.accessToken(), result.expiresAt(), result.role());
  }

  @PostMapping("/auth/signup")
  @ResponseStatus(HttpStatus.CREATED)
  @Operation(
      summary = "회원가입",
      description =
          "owner 계정을 만들고 /auth/token 과 같은 모양의 토큰을 바로 발급해요. 아이디는 앞뒤 공백을 지우고 소문자로 저장해요"
              + " (영소문자·숫자로 시작, 영소문자·숫자·. _ - 3~32자). 비밀번호 8~200자, display_name 은 선택(64자 이하, 비면 아이디)."
              + " 설정한 데모 프로젝트(기본 prj_demo_monolith)가 있으면 바로 참여시켜요."
              + " 대소문자만 다른 아이디도 409 USERNAME_TAKEN, IP 별 10분에 5번을 넘으면 429 RATE_LIMITED,"
              + " 회원가입을 꺼 두면 403 FORBIDDEN 이에요.")
  @ApiResponse(responseCode = "201", description = "가입 완료, 토큰 발급", useReturnTypeSchema = true)
  public TokenResponse signup(
      @Valid @RequestBody SignupRequest request, HttpServletRequest httpRequest) {
    AuthService.LoginResult result =
        signupService.signup(
            request.username(), request.password(), request.displayName(), clientIp(httpRequest));
    return new TokenResponse(result.accessToken(), result.expiresAt(), result.role());
  }

  @GetMapping("/auth/me")
  @Operation(
      summary = "내 계정 조회",
      description = "owner는 변경 가능, viewer는 조회 전용이에요. GitHub 로그인과는 별개예요.")
  @SecurityRequirement(name = "bearerAuth")
  public MeResponse me(@CurrentAccount AuthPrincipal principal) {
    return new MeResponse(principal.accountId(), principal.username(), principal.role());
  }

  public record LoginRequest(
      @NotBlank @Size(max = 128) String username, @NotBlank @Size(max = 200) String password) {}

  /** 아이디 형식·display_name 길이는 아이디를 다듬은 뒤 {@link SignupService} 가 확인해요. */
  public record SignupRequest(
      @NotBlank @Size(max = 128) String username,
      @NotBlank @Size(min = 8, max = 200) String password,
      @Size(max = 200) String displayName) {}

  public record TokenResponse(String accessToken, Instant expiresAt, String role) {}

  public record MeResponse(String accountId, String username, String role) {}

  /** 프록시 뒤라 X-Forwarded-For 첫 값을 써요. 없으면 접속 주소예요. 횟수 제한에만 써요. */
  private static String clientIp(HttpServletRequest request) {
    String forwarded = request.getHeader("X-Forwarded-For");
    if (forwarded != null) {
      String first = forwarded.split(",", 2)[0].trim();
      if (!first.isEmpty()) {
        return first;
      }
    }
    return request.getRemoteAddr();
  }
}
