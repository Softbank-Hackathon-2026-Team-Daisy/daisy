package com.teamdaisy.server.identity.web;

import com.teamdaisy.server.identity.auth.AuthPrincipal;
import com.teamdaisy.server.identity.auth.AuthService;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.security.SecurityRequirement;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;
import java.time.Instant;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RestController;

/** 로그인과 내 정보 조회예요. */
@RestController
public class AuthController {
  private final AuthService authService;

  public AuthController(AuthService authService) {
    this.authService = authService;
  }

  @PostMapping("/auth/token")
  @Operation(
      summary = "데모 계정 로그인",
      description =
          "환경 설정으로 준비된 계정의 토큰을 발급해요. 회원가입 API는 없어요. 토큰은 REST·SSE의 Authorization: Bearer 헤더에 전달해요.")
  public TokenResponse issueToken(@Valid @RequestBody LoginRequest request) {
    AuthService.LoginResult result = authService.login(request.username(), request.password());
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

  public record TokenResponse(String accessToken, Instant expiresAt, String role) {}

  public record MeResponse(String accountId, String username, String role) {}
}
