import Foundation

/// "결정이 필요한 배포" 규칙 (10/3 신선도 검수 O1 · H4, 배포 탭과 같은 기준).
/// 프로젝트의 가장 최근 배포(A-03 첫 건, 상태 거르지 않음)이고, 아직 승인 · 거절하지 않은 승인 대기 환경이 있을 때만이에요.
/// 이미 승인하고 apply만 기다리는 환경(`isApprovedWaiting`)은 결정할 게 없고,
/// 더 새 배포가 생긴 뒤 승인 대기로 남은 지난 배포는 버려진 배포라 "승인하기"를 보여주지 않아요.
enum DecisionRule {
    enum Status: Equatable {
        /// 가장 최근 배포 + 승인 안 된 환경 있음 → "승인하기"
        case needsDecision
        /// 가장 최근 배포인데 승인 대기 환경을 모두 승인했어요 → "승인 완료 · 실행 대기"
        case approvedWaiting
        /// 승인 대기로 남은 지난 배포 → "승인 대기 (지난 배포)"
        case abandoned
        /// 승인과 상관없어요
        case none
    }

    /// 목록(최신순)에서 지금 결정이 필요한 배포. 없으면 nil
    static func needingDecision(in deployments: [Deployment]) -> Deployment? {
        guard let newest = deployments.first, status(of: newest, newestID: newest.id) == .needsDecision else { return nil }
        return newest
    }

    static func status(of deployment: Deployment, newestID: String?) -> Status {
        guard !deployment.state.isFinished, deployment.state == .awaitingApproval || hasAwaitingTarget(deployment) else {
            return .none
        }
        guard deployment.id == newestID else { return .abandoned }
        return hasUndecidedTarget(deployment) ? .needsDecision : .approvedWaiting
    }

    private static func hasAwaitingTarget(_ deployment: Deployment) -> Bool {
        (deployment.targets ?? []).contains { $0.resolvedState == .awaitingApproval }
    }

    /// 승인 · 거절을 기다리는 환경이 있어요. 목록에 환경이 안 오면(서버 응답 모양) 배포 상태로 판단해요
    private static func hasUndecidedTarget(_ deployment: Deployment) -> Bool {
        guard let targets = deployment.targets, !targets.isEmpty else { return deployment.state == .awaitingApproval }
        return targets.contains { $0.resolvedState == .awaitingApproval && !$0.isApprovedWaiting }
    }
}

extension Deployment {
    /// 이력 · 개요 목록 배지. 승인 대기는 결정 규칙에 따라 "승인 대기" · "승인 완료 · 실행 대기" · "승인 대기 (지난 배포)"로 나눠요
    func listBadge(newestID: String?) -> StatusBadge {
        switch DecisionRule.status(of: self, newestID: newestID) {
        case .approvedWaiting: StatusBadge(text: .app("승인 완료 · 실행 대기"), color: .blue)
        case .abandoned: StatusBadge(text: .app("승인 대기 (지난 배포)"), color: .gray)
        case .needsDecision, .none: badge
        }
    }
}
