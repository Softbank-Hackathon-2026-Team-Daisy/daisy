package com.teamdaisy.server.identity.web;

import com.teamdaisy.server.identity.auth.AuthPrincipal;
import com.teamdaisy.server.identity.auth.AuthService;
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
  public TokenResponse issueToken(@Valid @RequestBody LoginRequest request) {
    AuthService.LoginResult result = authService.login(request.username(), request.password());
    return new TokenResponse(result.accessToken(), result.expiresAt(), result.role());
  }

  @GetMapping("/auth/me")
  @SecurityRequirement(name = "bearerAuth")
  public MeResponse me(@CurrentAccount AuthPrincipal principal) {
    return new MeResponse(principal.accountId(), principal.username(), principal.role());
  }

  public record LoginRequest(
      @NotBlank @Size(max = 128) String username, @NotBlank @Size(max = 200) String password) {}

  public record TokenResponse(String accessToken, Instant expiresAt, String role) {}

  public record MeResponse(String accountId, String username, String role) {}
}
