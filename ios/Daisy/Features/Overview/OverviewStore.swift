import Foundation
import Observation

/// 개요 (W-01): 최근 실행(A-03, 승인 대기 제외). 환경별 현재 버전 · 동일성 검증은 Workspace의 A-02로 만들어요.
@MainActor
@Observable
final class OverviewStore {
    private(set) var recent: [Deployment] = []

    func refresh(using app: AppModel) async {
        guard let client = app.client, let projectID = app.selectedProjectID else { return }
        // 웹: 승인 대기는 "지금 할 일"에 따로 보여서 최근 실행에서는 빼요
        let recent = try? await client.send(.deployments(projectID: projectID)).items.filter { $0.state != .awaitingApproval }
        self.recent = Array((recent ?? self.recent).prefix(3))
    }
}

extension [TargetStatus] {
    /// 배포된 첫 환경과 image digest(WR-09)가 같은 환경 수 ("3/3 일치"). 웹 개요와 같은 규칙이에요.
    var parityMatching: Int {
        let base = first { $0.current != nil }?.imageDigest
        return filter { $0.current != nil && $0.imageDigest != nil && $0.imageDigest == base }.count
    }
}

/// "세 환경", "두 환경" 같은 우리말 수
func koreanCount(_ n: Int) -> String {
    switch n {
    case 1: "한"
    case 2: "두"
    case 3: "세"
    case 4: "네"
    default: "\(n)개"
    }
}
