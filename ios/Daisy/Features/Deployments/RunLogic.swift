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
    /// 서버가 앱이 모르는 배포 상태를 보냈어요. 진행 중으로도 끝난 것으로도 보지 않고 "상태를 확인할 수 없어요" (D1, 10/3)
    case unknown

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
        case .succeeded, .partiallySucceeded, .failed, .cancelled:
            self = .result
        case .unknown:
            self = .unknown
        }
    }
}

/// "다시 시도" 요청: 원본 배포 ID + 다시 할 환경만 보내요 (`POST /deployments/{id}/retry`, 10/2 09:57 확정).
/// 서버가 원본에서 빌드 · 연결을 그대로 이어받아 새 배포를 만들고, 성공한 환경은 건드리지 않아요.
struct RetryRequest: Equatable {
    let deploymentID: String
    let targetIDs: [String]

    /// W-08 실패 카드 "다시 시도"
    static func only(_ targetID: String, of deployment: Deployment) -> RetryRequest {
        RetryRequest(deploymentID: deployment.id, targetIDs: [targetID])
    }

    /// W-05b "○○만 다시 시도": 실패한 환경 전부를 한 번에 (웹과 같아요)
    static func failed(of deployment: Deployment) -> RetryRequest {
        RetryRequest(deploymentID: deployment.id,
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
            return Stopped(title: .app("배포를 중단했어요"),
                           description: .app("모든 환경이 \(attempts)번 모두 실패해서 멈췄어요."),
                           toastTitle: .app("\(failedNames) 검증 실패 · 배포 중단"))
        }
        return Stopped(title: .app("\(failedNames)만 멈췄어요"),
                       description: .app("\(failedNames)는 \(attempts)번 모두 실패해서 멈췄어요. \(join(others.map { name($0.targetId) }))는 그대로 계속 진행해요."),
                       toastTitle: .app("\(failedNames) 검증 실패 · 나머지 환경은 계속"))
    }

    /// W-08 설명: 웹 "온프레미스 · AWS는 성공, GCP는 헬스체크에서 실패했어요. 성공한 환경끼리 같은 이미지인지 확인해요."
    static func result(_ deployment: Deployment, name: (String) -> String) -> String {
        let targets = deployment.targets ?? []
        let succeeded = targets.filter { !$0.isFailed && $0.state != .cancelled }
        let failed = targets.filter(\.isFailed)
        switch deployment.state {
        case .cancelled:
            return .app("배포를 취소했어요. 이미 바뀐 환경은 이력에서 확인해요.")
        case .failed where succeeded.isEmpty:
            return .app("모든 환경이 실패했어요. 원인을 확인하고 다시 시도해 주세요.")
        default:
            guard !failed.isEmpty else { return .app("모든 환경이 같은 이미지로 떠 있는지 확인해요.") }
            // 웹: 첫 실패 환경의 단계로 "헬스체크에서" · "apply에서"
            let ok = join(succeeded.map { name($0.targetId) })
            let bad = join(failed.map { name($0.targetId) })
            if failed[0].step == .healthCheck {
                return .app("\(ok)는 성공, \(bad)는 헬스체크에서 실패했어요. 성공한 환경끼리 같은 이미지인지 확인해요.")
            }
            return .app("\(ok)는 성공, \(bad)는 apply에서 실패했어요. 성공한 환경끼리 같은 이미지인지 확인해요.")
        }
    }
}

// MARK: - 새로고침 규칙 (데이터 신선도, 10/3 검수 D1 · D9 · D14)

/// 배포 한 건 화면(RunView)이 얼마나 자주, 언제까지 다시 받을지.
enum RunRefresh {
    /// 모르는 상태(D1): 진행 중으로 보지 않아요. 빠른 폴링 없이 30초마다만 다시 물어봐요
    static let unknownInterval: Double = 30
    /// 끝난 뒤(D14): 헬스 요약 · URL · digest가 조금 늦게 채워져서 30초마다 몇 분 더 받아요
    static let settleInterval: Double = 30
    static let settleWindow: TimeInterval = 180

    static func interval(state: DeploymentState?, live: Bool, loading: Bool) -> Double {
        switch state {
        case .unknown?: unknownInterval
        case let state? where state.isFinished: settleInterval
        default: PollInterval.seconds(live: live, active: loading || state?.isActive == true)
        }
    }

    /// 더 받지 않아도 될 때: 끝난 지 `settleWindow`가 지났어요.
    /// 끝난 시각은 서버 `finished_at`, 없으면 앱이 처음 끝난 걸 본 때예요 (이력에서 연 오래된 배포는 한 번만 받아요)
    static func isSettled(_ deployment: Deployment?, finishedSeenAt: Date?, now: Date) -> Bool {
        guard let deployment, deployment.state.isFinished else { return false }
        let finished = deployment.finishedAt ?? finishedSeenAt ?? now
        return now.timeIntervalSince(finished) >= settleWindow
    }

    /// 배포 채널(E-01)을 열어 둘 때: 아직 모르거나(첫 응답 전) 진행 중일 때만. 끝났거나 모르는 상태면 닫아요
    static func wantsChannel(_ state: DeploymentState?) -> Bool {
        state.map(\.isActive) ?? true
    }
}

/// 전환 로딩(L-02 · L-03)을 내릴 때 (D9). 전에는 상태가 바뀔 때까지 기다려서, 만들자마자 running인 배포는 진행 화면을 오래 가렸어요.
enum LoaderRule {
    /// 이 시간이 지나면 무조건 내려요
    static let cap: TimeInterval = 8

    /// - `from`: 로딩을 띄울 때(또는 처음 받은 응답)의 배포 상태. 상태가 바뀌면 내려요
    static func shouldDrop(_ stage: TransitionLoader.Stage, from: DeploymentState?, latest: Deployment, elapsed: TimeInterval) -> Bool {
        if elapsed >= cap { return true }
        if let from, latest.state != from { return true }
        let targets = latest.targets ?? []
        switch stage {
        case .generate:
            // 한 환경이라도 생성을 시작했으면(대기 · 모름이 아니면) 진행 화면이 더 많은 걸 보여줘요
            return RunStage(latest) != .generate || targets.contains { ![.waiting, .unknown].contains($0.resolvedState) }
        case .deploy:
            return RunStage(latest) != .approval || targets.contains(where: \.reachedApply)
        case .repository:
            return true
        }
    }
}

// MARK: - 배포 탭이 보여줄 배포 (D2)

/// 배포 탭 루트가 보여줄 배포와 "새 배포가 시작됐어요 · 보기" 배너.
/// - 가장 최근 배포가 진행 중이면 그걸 보여줘요. 보던 배포가 끝나면 벗어나기 전까지 결과를 보여줘요 (#124).
/// - 보던 배포가 승인 대기(W-06, 삭제 확인을 입력하는 중일 수 있어요)인데 더 새 배포가 생기면 화면을 바꾸지 않고 배너로 알려요.
/// - 이 화면에서 방금 시작한 배포(`requested`)는 목록에 아직 없어도 먼저 보여줘요.
struct DeploymentsFocus: Equatable {
    let shown: String?
    /// 배너로 알릴 더 새 배포
    let newer: String?

    init(shown: String?, newer: String?) {
        (self.shown, self.newer) = (shown, newer)
    }

    init(list: [Deployment], displayed: String?, requested: String?) {
        let active = list.first.flatMap { $0.state.isFinished ? nil : $0 }
        if let requested, !list.contains(where: { $0.id == requested }) {
            (shown, newer) = (requested, nil)
            return
        }
        // 목록에 없는 배포는 잊어요 (프로젝트를 바꿨거나 목록에서 밀려났어요)
        let kept = displayed.flatMap { id in list.contains { $0.id == id } ? id : nil }
        guard let current = requested ?? kept else {
            (shown, newer) = (active?.id, nil)
            return
        }
        guard let active, active.id != current else {
            (shown, newer) = (current, nil)
            return
        }
        // 더 새 배포가 진행 중이에요
        if list.first(where: { $0.id == current })?.state == .awaitingApproval {
            (shown, newer) = (current, active.id)
        } else {
            (shown, newer) = (active.id, nil)
        }
    }
}

// MARK: - 같은 배포 화면을 두 번 쌓지 않기 (D12 · D13 · P5)

enum RunNavigation {
    /// 배포 탭 루트가 이어받을 배포 화면
    struct Adoption: Equatable {
        let deploymentID: String
        let loader: TransitionLoader.Stage?
    }

    /// 배포 탭 경로 맨 위가 루트가 이미 보여주는 배포이거나 방금 시작한 배포(`.started`)면, 루트가 이어받고 경로를 비워요.
    /// 안 그러면 같은 배포 화면이 두 개(채널도 두 개) 생겨요 (다시 시도 · 새 배포 시작 · 알림 · 승인 뒤 배포 화면)
    static func adoption(of path: [Route], rootShows: String?) -> Adoption? {
        switch path.last {
        case .started(let id)?: Adoption(deploymentID: id, loader: .generate)
        case .run(let id)? where id == rootShows: Adoption(deploymentID: id, loader: nil)
        default: nil
        }
    }

    /// 다시 시도로 새 배포가 생겼을 때 경로: 맨 위가 원래 배포 화면이면 바꿔 끼우고, 아니면 위에 열어요
    static func afterRetry(_ path: [Route], started id: String, source: String) -> [Route] {
        var path = path
        if path.last?.runDeploymentID == source { path.removeLast() }
        path.append(.started(id))
        return path
    }
}

extension Route {
    /// 배포 한 건 화면(RunView)이면 그 배포 ID
    var runDeploymentID: String? {
        switch self {
        case .run(let id), .started(let id): id
        default: nil
        }
    }
}

// MARK: - 승인 화면 (A1 · A2 · A3)

/// 승인 화면을 다시 그려야 하는 배포 변화: 상태 · 환경별 상태 · 승인 상태 · 시도 · 승인 ID.
/// 이 값이 바뀌면 plan(A-05)도 다시 받아요 (웹에서 승인 · 거절, plan.stale로 새 plan이 뜬 경우)
struct ApprovalFingerprint: Equatable {
    struct Row: Equatable {
        let targetID: String
        let state: TargetState
        let approval: Deployment.Target.ApprovalState?
        let attempt: Int
    }

    let state: DeploymentState
    let rows: [Row]
    let approvals: Set<Deployment.ApprovalItem>

    init(_ deployment: Deployment) {
        state = deployment.state
        rows = (deployment.targets ?? []).map {
            Row(targetID: $0.targetId, state: $0.resolvedState, approval: $0.approvalState, attempt: $0.attempt)
        }
        approvals = Set(deployment.pendingApprovals ?? [])
    }
}

/// 승인 화면이 지금 보여줄 것
enum ApprovalPhase: Equatable {
    /// 승인 바
    case approvable
    /// 이미 승인했고 apply를 기다려요 (웹 #64)
    case approvedWaiting
    /// 승인할 환경이 없어요: 다른 곳에서 처리됐거나 plan이 만료 · 교체됐거나 아직 검증 중
    case nothing
    /// 배포가 승인 단계를 지났어요 (apply 시작 · 끝 · 다시 생성). 따로 연 승인 화면은 배포 화면으로 넘어가요
    case movedOn

    init(deployment: Deployment?, approvable: Int, approvedWaiting: Int) {
        if let deployment, RunStage(deployment) != .approval {
            self = .movedOn
        } else if approvable > 0 {
            self = .approvable
        } else if approvedWaiting > 0 {
            self = .approvedWaiting
        } else {
            self = .nothing
        }
    }
}
