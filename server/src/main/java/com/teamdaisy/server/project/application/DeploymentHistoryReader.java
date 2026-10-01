package com.teamdaisy.server.project.application;

import com.teamdaisy.server.common.error.DaisyException;
import com.teamdaisy.server.common.error.ErrorCode;
import com.teamdaisy.server.deployment.application.DeploymentQueryService;
import com.teamdaisy.server.deployment.application.DeploymentQueryService.CurrentDeployment;
import com.teamdaisy.server.deployment.application.DeploymentQueryService.CurrentPointer;
import com.teamdaisy.server.deployment.application.DeploymentQueryService.SuccessfulDeployment;
import com.teamdaisy.server.project.domain.Target;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Component;

/**
 * A-02 {@code current}·A-06 {@code deployed_to} 를 승환의 배포 조회 서비스로 채워요 (server/SPEC.md ⑤).
 *
 * <p><b>대상 하나가 화면 전체를 깨지 않게 해요.</b> {@code current()} 는 포인터 하나만 잘못돼도 전체를 409 로 거절해요. 그러면 앱 핵심 화면이
 * 대상 하나 때문에 비게 돼요. 그래서 일괄 호출이 실패하면 대상별로 다시 불러 문제 대상만 {@code unverified} 로 둬요.
 *
 * <p><b>일부러 트랜잭션을 걸지 않아요.</b> 조회 서비스는 {@code @Transactional(readOnly = true)} 라, 바깥 트랜잭션 안에서 부르면
 * 예외가 나는 순간 바깥까지 롤백 전용이 돼요. 예외를 잡고 계속 가도 마지막 커밋에서 {@code UnexpectedRollbackException} 으로 500 이 나요.
 * 그래서 대상 목록 조회와 이 호출을 각자의 트랜잭션으로 돌려요. 지금은 포인터를 바꾸는 곳이 없어 두 조회 사이에 값이 달라지지 않아요.
 */
@Component
public class DeploymentHistoryReader {
  public static final String NONE = "none";
  public static final String CONFIRMED = "confirmed";
  public static final String UNVERIFIED = "unverified";

  private static final Logger LOG = LoggerFactory.getLogger(DeploymentHistoryReader.class);
  private static final int BATCH = 100;
  // 대상의 문제라서 격리할 오류예요. 권한 오류(403)·입력 오류(400)는 요청의 문제라 그대로 올려요.
  private static final Set<ErrorCode> TARGET_FAULTS =
      Set.of(ErrorCode.NOT_FOUND, ErrorCode.STATE_CONFLICT);

  private final DeploymentQueryService queries;

  public DeploymentHistoryReader(DeploymentQueryService queries) {
    this.queries = queries;
  }

  /**
   * 대상별 현재 배포예요.
   *
   * @param status {@code none} 포인터 없음(확인된 현재 참조 없음 — 배포가 없다는 뜻이 아니에요), {@code confirmed} 확인됨,
   *     {@code unverified} 포인터는 있으나 확인 실패
   */
  public record CurrentView(String status, CurrentDeployment deployment) {
    static final CurrentView NONE_VIEW = new CurrentView(NONE, null);
    static final CurrentView UNVERIFIED_VIEW = new CurrentView(UNVERIFIED, null);

    public static CurrentView none() {
      return NONE_VIEW;
    }
  }

  /** 호출하는 쪽이 이미 이 프로젝트의 조회 권한을 확인했다고 봐요. 그래서 대상별로 다시 부를 때 나는 404 는 권한이 아니라 대상의 문제로 읽어요. */
  public Map<String, CurrentView> current(String actorId, String projectId, List<Target> targets) {
    Map<String, CurrentView> views = new HashMap<>();
    List<Target> pointed =
        targets.stream().filter(target -> target.currentDeploymentTargetId() != null).toList();
    for (Target target : targets) {
      views.put(target.id(), CurrentView.none());
    }
    if (pointed.isEmpty()) {
      // 포인터가 하나도 없으면 부르지 않아요. 지금은 갱신하는 곳이 없어 늘 이 경로예요.
      return views;
    }
    for (int from = 0; from < pointed.size(); from += BATCH) {
      List<Target> chunk = pointed.subList(from, Math.min(from + BATCH, pointed.size()));
      try {
        Map<String, CurrentDeployment> found = queries.current(actorId, projectId, pointers(chunk));
        for (Target target : chunk) {
          CurrentDeployment deployment = found.get(target.id());
          // 포인터가 있는데 결과에 없으면 "없음" 이 아니라 "확인 못 함" 이에요.
          views.put(
              target.id(),
              deployment == null
                  ? CurrentView.UNVERIFIED_VIEW
                  : new CurrentView(CONFIRMED, deployment));
        }
      } catch (DaisyException batchFailure) {
        if (!TARGET_FAULTS.contains(batchFailure.errorCode())) {
          throw batchFailure;
        }
        for (Target target : chunk) {
          views.put(target.id(), single(actorId, projectId, target));
        }
      }
    }
    return views;
  }

  /**
   * 빌드별·대상별 마지막 성공 이력이에요.
   *
   * <p>조회했는데 성공 이력이 없으면 빈 목록이에요. 과거 성공 이력이지 지금 그 버전이 떠 있다는 뜻이 아니에요.
   */
  public Map<String, List<SuccessfulDeployment>> deployedTo(
      String actorId, String projectId, List<String> sourceVersionIds) {
    if (sourceVersionIds.isEmpty()) {
      return Map.of();
    }
    return queries.deployedTo(actorId, projectId, sourceVersionIds);
  }

  private CurrentView single(String actorId, String projectId, Target target) {
    try {
      CurrentDeployment found =
          queries.current(actorId, projectId, pointers(List.of(target))).get(target.id());
      return found == null ? CurrentView.UNVERIFIED_VIEW : new CurrentView(CONFIRMED, found);
    } catch (DaisyException failure) {
      if (!TARGET_FAULTS.contains(failure.errorCode())) {
        throw failure;
      }
      LOG.warn(
          "현재 배포를 확인하지 못했어요. targetId={} pointer={} code={}",
          target.id(),
          target.currentDeploymentTargetId(),
          failure.errorCode());
      return CurrentView.UNVERIFIED_VIEW;
    }
  }

  private static List<CurrentPointer> pointers(List<Target> targets) {
    return targets.stream()
        .map(target -> new CurrentPointer(target.id(), target.currentDeploymentTargetId()))
        .toList();
  }
}
