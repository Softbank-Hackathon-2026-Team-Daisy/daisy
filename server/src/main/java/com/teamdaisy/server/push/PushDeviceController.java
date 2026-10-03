package com.teamdaisy.server.push;

import com.teamdaisy.server.identity.auth.AuthPrincipal;
import com.teamdaisy.server.identity.web.CurrentAccount;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.media.Schema;
import io.swagger.v3.oas.annotations.security.SecurityRequirement;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

/**
 * 앱 푸시 기기 등록·해제 API 예요 (ios/SPEC.md §6-5 P-01, 9/29 합의).
 *
 * <p>토큰을 URL 경로에 넣으면 서버·프록시 로그에 남아서 해제도 본문으로 받아요.
 */
@RestController
@SecurityRequirement(name = "bearerAuth")
public class PushDeviceController {
  private final PushDeviceService devices;

  public PushDeviceController(PushDeviceService devices) {
    this.devices = devices;
  }

  public record RegisterDevice(
      @Schema(
              requiredMode = Schema.RequiredMode.REQUIRED,
              description = "APNs 기기 토큰(16진수 32~200자)",
              example = "4f0c2e6a9b7d4c1e8a3f5b2d7c9e1a4f6b8d0c2e4a6f8b0d2c4e6a8f0b2d4c6e")
          String apnsToken,
      @Schema(
              requiredMode = Schema.RequiredMode.REQUIRED,
              allowableValues = {"ios", "macos"})
          String platform,
      @Schema(
              requiredMode = Schema.RequiredMode.REQUIRED,
              allowableValues = {"production", "sandbox"},
              description = "TestFlight·배포 빌드는 production, Xcode 개발 빌드는 sandbox")
          String apnsEnv) {}

  public record UnregisterDevice(
      @Schema(requiredMode = Schema.RequiredMode.REQUIRED, description = "APNs 기기 토큰")
          String apnsToken) {}

  @PostMapping("/devices")
  @Operation(
      summary = "푸시 기기 등록",
      description =
          "로그인한 계정에 APNs 토큰을 묶어요. 같은 토큰을 다시 보내면 지금 계정으로 옮기고 platform·apns_env 를 바꾸며 다시 켜요. "
              + "읽기 전용 계정도 등록할 수 있어요.")
  @ResponseStatus(HttpStatus.NO_CONTENT)
  public void register(
      @CurrentAccount AuthPrincipal principal, @RequestBody RegisterDevice request) {
    devices.register(principal, request.apnsToken(), request.platform(), request.apnsEnv());
  }

  @DeleteMapping("/devices")
  @Operation(
      summary = "푸시 기기 해제",
      description = "내 계정에 묶인 토큰이면 지워요. 모르는 토큰이나 다른 계정의 토큰이어도 아무것도 바꾸지 않고 204예요.")
  @ResponseStatus(HttpStatus.NO_CONTENT)
  public void unregister(
      @CurrentAccount AuthPrincipal principal, @RequestBody UnregisterDevice request) {
    devices.unregister(principal, request.apnsToken());
  }
}
