package com.teamdaisy.server.project.application;

import com.teamdaisy.server.deployment.application.DeploymentQueryService;
import com.teamdaisy.server.deployment.application.DeploymentQueryService.CurrentDeployment;
import com.teamdaisy.server.deployment.application.DeploymentQueryService.CurrentPointer;
import com.teamdaisy.server.deployment.application.DeploymentQueryService.CurrentResult;
import com.teamdaisy.server.deployment.application.DeploymentQueryService.SuccessfulDeployment;
import com.teamdaisy.server.project.domain.Target;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import org.springframework.stereotype.Component;

/**
 * A-02 {@code current}·A-06 {@code deployed_to} 를 승환의 배포 조회 서비스로 채워요 (server/SPEC.md ⑤).
 *
 * <p>{@code currentByTarget} 은 포인터 확인에 실패한 대상을 예외 없이 {@code unverified} 로 돌려줘요. 그래서 대상 하나가 화면 전체를
 * 깨지 않고, 목록 조회와 같은 읽기 트랜잭션에서 불러도 돼요. 권한 오류(401·403·404)와 입력 오류는 조회 서비스가 그대로 올려요 (#42, 044a436).
 */
@Component
public class DeploymentHistoryReader {
  public static final String NONE = "none";
  public static final String CONFIRMED = "confirmed";
  public static final String UNVERIFIED = "unverified";

  private static final int BATCH = 100;

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

    public static CurrentView none() {
      return NONE_VIEW;
    }
  }

  public Map<String, CurrentView> current(String actorId, String projectId, List<Target> targets) {
    Map<String, CurrentView> views = new HashMap<>();
    for (Target target : targets) {
      views.put(target.id(), CurrentView.none());
    }
    if (targets.stream().noneMatch(target -> target.currentDeploymentTargetId() != null)) {
      // 포인터가 하나도 없으면 부르지 않아요. 지금은 갱신하는 곳이 없어 늘 이 경로예요.
      return views;
    }
    for (int from = 0; from < targets.size(); from += BATCH) {
      List<Target> chunk = targets.subList(from, Math.min(from + BATCH, targets.size()));
      Map<String, CurrentResult> found =
          queries.currentByTarget(actorId, projectId, pointers(chunk));
      found.forEach(
          (targetId, result) ->
              views.put(targetId, new CurrentView(result.status(), result.deployment())));
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

  private static List<CurrentPointer> pointers(List<Target> targets) {
    return targets.stream()
        .map(target -> new CurrentPointer(target.id(), target.currentDeploymentTargetId()))
        .toList();
  }
}
