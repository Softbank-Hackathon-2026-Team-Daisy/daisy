package com.teamdaisy.server.push;

import com.teamdaisy.server.push.PushDeviceStore.Device;
import java.util.Set;

/** APNs 로 알림 하나를 보내요. 테스트에서는 가짜로 바꿔 끼워요. */
public interface ApnsSender {
  /** 키·키 ID 가 설정돼 실제로 보낼 수 있는지예요. */
  boolean enabled();

  /** 한 번만 시도해요. 네트워크 오류도 예외 대신 결과로 돌려줘요. */
  Result send(Device device, String collapseId, String payloadJson);

  /**
   * APNs 응답이에요. {@code status} 0 은 응답을 못 받은 경우예요.
   *
   * @param reason APNs 오류 본문의 {@code reason}. 성공이면 null
   */
  record Result(int status, String reason) {
    private static final Set<String> GONE =
        Set.of("BadDeviceToken", "Unregistered", "DeviceTokenNotForTopic");

    public boolean ok() {
      return status == 200;
    }

    /** 이 토큰으로는 다시 보내도 소용없는 응답이에요. 기기를 꺼요. */
    public boolean deviceGone() {
      return status == 410 || (status == 400 && reason != null && GONE.contains(reason));
    }
  }

  /** 키가 없을 때 쓰는 발송기예요. 발송기는 이 값을 보고 커서만 앞으로 옮겨요. */
  static ApnsSender disabled() {
    return new ApnsSender() {
      @Override
      public boolean enabled() {
        return false;
      }

      @Override
      public Result send(Device device, String collapseId, String payloadJson) {
        return new Result(0, "Disabled");
      }
    };
  }
}
