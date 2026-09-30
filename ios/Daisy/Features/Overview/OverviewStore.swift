import Foundation
import Observation

/// 개요 (W-01): 동일성 검증(가칭 A-09)과 최근 실행(A-03). 환경별 현재 버전은 Workspace가 가져요.
@MainActor
@Observable
final class OverviewStore {
    private(set) var parity: Parity?
    private(set) var recent: [Deployment] = []

    func refresh(using app: AppModel) async {
        guard let client = app.client, let projectID = app.selectedProjectID else { return }
        async let parity = try? client.send(.parity(projectID: projectID))
        async let recent = try? client.send(.deployments(projectID: projectID)).items
        self.parity = await parity ?? self.parity
        self.recent = Array((await recent ?? self.recent).prefix(3))
    }
}

extension [TargetStatus] {
    /// 배포된 환경이 모두 같은 커밋인지. 이식성("같은 이미지를 모든 환경에")을 보여주는 값이에요.
    var deployedCommits: Set<String> { Set(compactMap { $0.current?.commit }) }
    var isConsistent: Bool { deployedCommits.count <= 1 }

    /// 가장 많은 환경이 쓰는 이미지에 몇 개 환경이 맞는지 ("3/3 일치").
    var parity: (matching: Int, deployed: Int) {
        let commits = compactMap { $0.current?.commit }
        let counts = Dictionary(commits.map { ($0, 1) }, uniquingKeysWith: +)
        return (counts.values.max() ?? 0, commits.count)
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
