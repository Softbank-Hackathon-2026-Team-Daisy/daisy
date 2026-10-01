import Foundation

// 배포 한 건 화면의 판단 규칙. 화면과 떼어 두어 테스트로 근거를 남겨요 (DaisyTests/RunLogicTests).

/// 지금 보여줄 웹 흐름 화면.
enum RunStage: Equatable {
    /// W-05 생성 · 검증
    case generate
    /// W-05b 한 환경(이상)이 apply 전에 3회 실패. 나머지는 계속 진행하거나 모두 멈춘 상태
    case stopped
    /// W-06 승인
    case approval
    /// W-07 배포 중
    case apply
    /// W-08 결과
    case result

    init(_ deployment: Deployment) {
        let targets = deployment.targets ?? []
        let applying = targets.contains(where: \.reachedApply)
        let failedEarly = targets.contains { $0.isFailed && !$0.reachedApply }
        switch deployment.state {
        case .awaitingApproval:
            self = .approval
        case .queued, .running:
            self = applying ? .apply : failedEarly ? .stopped : .generate
        case .failed where !applying:
            self = .stopped
        case .succeeded, .partiallySucceeded, .failed, .cancelled, .unknown:
            self = .result
        }
    }
}

/// "다시 시도"가 만드는 새 배포 요청 (WR-05). 같은 커밋으로 고른 환경만 다시 해요.
struct RetryRequest: Equatable {
    let projectID: String
    let commit: String
    let targetIDs: [String]

    /// W-05b "AWS만 다시 시도", W-08 실패 카드 "다시 시도"
    static func only(_ targetID: String, of deployment: Deployment) -> RetryRequest {
        RetryRequest(projectID: deployment.projectId, commit: deployment.commit, targetIDs: [targetID])
    }

    /// W-05b "AWS만 다시 시도": 실패한 환경 전부를 한 번에 (웹과 같아요)
    static func failed(of deployment: Deployment) -> RetryRequest {
        RetryRequest(projectID: deployment.projectId, commit: deployment.commit,
                     targetIDs: (deployment.targets ?? []).filter(\.isFailed).map(\.targetId))
    }
}

/// W-05b · W-08 문구. 환경 이름은 화면이 넘겨줘요 (Workspace.name(of:)).
enum FlowCopy {
    /// "온프레미스 · GCP"
    static func join(_ names: [String]) -> String { names.joined(separator: " · ") }

    struct Stopped: Equatable {
        let title: String
        let description: String
        let toastTitle: String
    }

    /// W-05b: 웹 "AWS만 멈췄어요 / AWS는 3번 모두 실패해서 멈췄어요. 온프레미스 · GCP는 그대로 계속 진행해요."
    static func stopped(_ deployment: Deployment, name: (String) -> String) -> Stopped {
        let targets = deployment.targets ?? []
        let failed = targets.filter(\.isFailed)
        let others = targets.filter { !$0.isFailed }
        let failedNames = join(failed.map { name($0.targetId) })
        let attempts = failed.map(\.attempt).max() ?? 3
        if others.isEmpty {
            return Stopped(title: "배포를 중단했어요",
                           description: "모든 환경이 \(attempts)번 모두 실패해서 멈췄어요.",
                           toastTitle: "\(failedNames) 검증 실패 · 배포 중단")
        }
        return Stopped(title: "\(failedNames)만 멈췄어요",
                       description: "\(failedNames)는 \(attempts)번 모두 실패해서 멈췄어요. \(join(others.map { name($0.targetId) }))는 그대로 계속 진행해요.",
                       toastTitle: "\(failedNames) 검증 실패 · 나머지 환경은 계속")
    }

    /// W-08 설명: 웹 "온프레미스 · AWS는 성공, GCP는 헬스체크에서 실패했어요. 성공한 환경끼리 같은 이미지인지 확인해요."
    static func result(_ deployment: Deployment, name: (String) -> String) -> String {
        let targets = deployment.targets ?? []
        let succeeded = targets.filter { !$0.isFailed && $0.state != .cancelled }
        let failed = targets.filter(\.isFailed)
        switch deployment.state {
        case .cancelled:
            return "배포를 취소했어요. 이미 바뀐 환경은 이력에서 확인해요."
        case .failed where succeeded.isEmpty:
            return "모든 환경이 실패했어요. 원인을 확인하고 다시 시도해 주세요."
        default:
            guard !failed.isEmpty else { return "모든 환경이 같은 이미지로 떠 있는지 확인해요." }
            // 웹: 첫 실패 환경의 단계로 "헬스체크에서" · "apply에서"
            let where_ = failed[0].step == .healthCheck ? "헬스체크에서 " : "apply에서 "
            return "\(join(succeeded.map { name($0.targetId) }))는 성공, \(join(failed.map { name($0.targetId) }))는 \(where_)실패했어요. 성공한 환경끼리 같은 이미지인지 확인해요."
        }
    }
}
