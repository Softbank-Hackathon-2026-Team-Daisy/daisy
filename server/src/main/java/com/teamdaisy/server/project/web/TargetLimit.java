package com.teamdaisy.server.project.web;

import com.teamdaisy.server.common.error.DaisyException;
import com.teamdaisy.server.common.error.ErrorCode;
import java.util.List;

/**
 * 요청 하나에 담을 수 있는 대상 수의 상한이에요.
 *
 * <p>실행 서비스는 프로젝트 행을 잠근 채 대상을 하나씩 확인해요. 개수에 상한이 없으면 한 요청이 그 프로젝트의 다른 배포 명령을 오래 막을 수 있어서, 잠그기 전에 여기서
 * 400 으로 끊어요. 50 은 데모 대상(3개)보다 넉넉하게 잡은 값이에요.
 */
final class TargetLimit {
  static final int MAX = 50;

  private TargetLimit() {}

  /** null 은 그대로 넘겨요. 비었는지·중복인지는 실행 서비스가 봐요. */
  static <T> List<T> check(List<T> values) {
    if (values != null && values.size() > MAX) {
      throw new DaisyException(ErrorCode.VALIDATION_FAILED);
    }
    return values;
  }
}
