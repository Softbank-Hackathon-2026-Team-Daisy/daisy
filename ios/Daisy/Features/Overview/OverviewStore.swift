import Foundation
import Observation

/// 개요 (W-01): 최근 실행(A-03). 환경별 현재 버전 · 동일성 검증은 Workspace의 A-02로 만들어요.
@MainActor
@Observable
final class OverviewStore {
    private(set) var recent: [Deployment] = []

    func refresh(using app: AppModel) async {
        guard let client = app.client, let projectID = app.selectedProjectID else { return }
        let recent = try? await client.send(.deployments(projectID: projectID)).items
        self.recent = Array((recent ?? self.recent).prefix(3))
    }
}

extension [TargetStatus] {
    /// 가장 많은 환경이 쓰는 이미지에 몇 개 환경이 맞는지 ("3/3 일치").
    /// 근거는 image digest(WR-09)예요. 서버가 아직 안 주면 커밋으로 대신해요.
    var parity: (matching: Int, deployed: Int) {
        let images = compactMap { $0.imageDigest ?? $0.current?.commit }
        let counts = Dictionary(images.map { ($0, 1) }, uniquingKeysWith: +)
        return (counts.values.max() ?? 0, images.count)
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
