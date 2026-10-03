import Foundation
import Observation

/// 개요 (W-01): "지금 할 일"과 "최근 실행"을 같은 A-03 응답 하나에서 만들어요 (10/3 신선도 검수 O4).
/// 환경별 현재 버전 · 동일성 검증은 Workspace의 A-02로 만들어요.
@MainActor
@Observable
final class OverviewStore {
    private let runs = ScopedLoader<[Deployment]>()

    var staleSince: Date? { runs.staleSince }

    func state(for projectID: String?) -> LoadState<Board> {
        switch runs.state(for: projectID) {
        case .idle: .idle
        case .loading: .loading
        case .failed(let message): .failed(message)
        case .loaded(let deployments): .loaded(Board(deployments))
        }
    }

    /// 진행 중이거나 결정이 필요한 배포가 있으면 폴링을 짧게 해요 (O2)
    func hasActive(for projectID: String?) -> Bool {
        runs.value(for: projectID)?.contains { [.queued, .running].contains($0.state) } == true
            || state(for: projectID).value?.todo != nil
    }

    func refresh(using app: AppModel) async {
        guard let client = app.client, let projectID = app.selectedProjectID else { return }
        await runs.load(projectID, using: app) {
            try await client.send(.deployments(projectID: projectID)).items
        }
    }

    /// 한 응답(A-03, 최신순)에서 나눈 "지금 할 일"과 "최근 실행"
    struct Board: Equatable {
        /// 결정이 필요한 배포 (가장 최근 배포 + 승인 안 된 환경). 없으면 할 일이 없어요 (O1)
        let todo: Deployment?
        /// 할 일로 보여준 배포를 뺀 최근 3건
        let recent: [Deployment]
        /// 가장 최근 배포 ID. 지난 승인 대기 배포를 "승인 대기 (지난 배포)"로 보여줄 때 써요
        let newestID: String?

        init(_ deployments: [Deployment]) {
            let todo = DecisionRule.needingDecision(in: deployments)
            self.todo = todo
            // 웹: 승인할 배포는 "지금 할 일"에 따로 보여서 최근 실행에서는 빼요
            recent = Array(deployments.filter { $0.id != todo?.id }.prefix(3))
            newestID = deployments.first?.id
        }
    }
}

extension [TargetStatus] {
    /// 배포된 첫 환경과 image digest(WR-09)가 같은 환경 수 ("3/3 일치"). 웹 개요와 같은 규칙이에요.
    var parityMatching: Int {
        let base = first { $0.current != nil }?.imageDigest
        return filter { $0.current != nil && $0.imageDigest != nil && $0.imageDigest == base }.count
    }
}

/// "세 환경", "두 환경" 같은 우리말 수. 한국어가 아니면 숫자 그대로예요 ("3 environments")
func koreanCount(_ n: Int) -> String {
    guard AppLanguage.current == .korean else { return n.appFormatted }
    return switch n {
    case 1: "한"
    case 2: "두"
    case 3: "세"
    case 4: "네"
    default: "\(n)개"
    }
}
