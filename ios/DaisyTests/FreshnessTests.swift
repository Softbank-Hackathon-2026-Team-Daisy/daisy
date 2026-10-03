import Foundation
import Testing
@testable import Daisy

/// 배포 흐름 · 승인 화면의 데이터 신선도 규칙 (10/3 검수 D1 · D2 · D9 · D12 · D14 · A1 – A3).
/// 근거: `freshness-audit-2026-10-03.md`의 항목 ID.
@MainActor
struct FreshnessTests {
    typealias F = Fixture

    /// 배포 ID · 상태 · 환경을 정해서 만들어요 (목록 규칙에는 서로 다른 ID가 필요해요)
    private func deployment(_ id: String, _ state: String, targets: [String] = [], extra: String = "") throws -> Deployment {
        let json = #"""
        { "id": "\#(id)", "project_id": "prj_1", "commit": "a1b2c3d4e5f6", "state": "\#(state)",
          "targets": [\#(targets.joined(separator: ","))]\#(extra.isEmpty ? "" : ", " + extra) }
        """#
        return try JSONDecoder.daisy.decode(Deployment.self, from: Data(json.utf8))
    }

    /// 승인 상태가 붙은 환경 한 줄
    private func approvalTarget(_ id: String, state: String = "awaiting_approval", approval: String) -> String {
        #"{ "target_id": "\#(id)", "state": "\#(state)", "step": "risk_check", "step_state": "done", "attempt": 1, "approval_state": "\#(approval)" }"#
    }

    private func pending(_ items: [(String, String)]) -> String {
        #""pending_approvals": ["# + items.map { #"{ "target_id": "\#($0.0)", "approval_id": "\#($0.1)" }"# }.joined(separator: ",") + "]"
    }

    // MARK: D1 모르는 상태

    @Test func unknownStateIsNotInProgress() throws {
        let unknown = try deployment("dep_1", "rolling_back", targets: [F.target("tgt_aws", step: "apply", stepState: "running")])
        #expect(unknown.state == .unknown)
        #expect(RunStage(unknown) == .unknown)
        // 빠른 폴링(2초) 없이 30초, 배포 채널도 열지 않아요
        #expect(RunRefresh.interval(state: .unknown, live: false, loading: false) == RunRefresh.unknownInterval)
        #expect(!RunRefresh.wantsChannel(.unknown))
        #expect(RunRefresh.wantsChannel(.running))
        #expect(RunRefresh.wantsChannel(nil))   // 첫 응답 전
        #expect(!RunRefresh.wantsChannel(.succeeded))
    }

    // MARK: D14 끝난 뒤 잠시 더

    @Test func finishedDeploymentSettlesAfterWindow() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let fresh = try deployment("dep_1", "succeeded")
        // finished_at이 없으면 앱이 처음 본 때부터 3분
        #expect(!RunRefresh.isSettled(fresh, finishedSeenAt: now, now: now))
        #expect(!RunRefresh.isSettled(fresh, finishedSeenAt: now, now: now.addingTimeInterval(60)))
        #expect(RunRefresh.isSettled(fresh, finishedSeenAt: now, now: now.addingTimeInterval(RunRefresh.settleWindow)))
        // 이력에서 연 오래된 배포는 한 번 받고 멈춰요
        let old = try deployment("dep_2", "succeeded", extra: #""finished_at": "2026-10-01T00:00:00Z""#)
        #expect(RunRefresh.isSettled(old, finishedSeenAt: now, now: now))
        // 진행 중 · 모르는 상태는 멈추지 않아요
        #expect(!RunRefresh.isSettled(try deployment("dep_3", "running"), finishedSeenAt: nil, now: now))
        #expect(!RunRefresh.isSettled(try deployment("dep_4", "rolling_back"), finishedSeenAt: nil, now: now))
        #expect(RunRefresh.interval(state: .succeeded, live: true, loading: false) == RunRefresh.settleInterval)
        #expect(RunRefresh.interval(state: .running, live: false, loading: false) == PollInterval.whileActive)
    }

    // MARK: D9 전환 로딩

    @Test func generateLoaderDropsOnProgressOrCap() throws {
        let waiting = try deployment("dep_1", "running", targets: [F.target("tgt_aws", state: "waiting", step: "generate", stepState: "waiting")])
        let generating = try deployment("dep_1", "running", targets: [F.target("tgt_aws", state: "generating", step: "generate", stepState: "running")])
        // 만들자마자 running이어도 아직 아무 환경도 시작 안 했으면 잠깐 보여줘요
        #expect(!LoaderRule.shouldDrop(.generate, from: nil, latest: waiting, elapsed: 1))
        // 한 환경이라도 생성을 시작하면 바로 내려요 (전에는 상태가 바뀔 때까지 가렸어요)
        #expect(LoaderRule.shouldDrop(.generate, from: .running, latest: generating, elapsed: 1))
        // 아무 변화가 없어도 상한이 지나면 내려요
        #expect(LoaderRule.shouldDrop(.generate, from: .running, latest: waiting, elapsed: LoaderRule.cap))
        // queued → running
        let queued = try deployment("dep_1", "queued", targets: [F.target("tgt_aws", state: "waiting", step: "generate", stepState: "waiting")])
        #expect(!LoaderRule.shouldDrop(.generate, from: .queued, latest: queued, elapsed: 2))
        #expect(LoaderRule.shouldDrop(.generate, from: .queued, latest: waiting, elapsed: 2))
    }

    @Test func deployLoaderWaitsForApply() throws {
        let approved = try deployment("dep_1", "awaiting_approval", targets: [approvalTarget("tgt_aws", approval: "approved")])
        let applying = try deployment("dep_1", "running", targets: [F.target("tgt_aws", state: "applying", step: "apply", stepState: "running")])
        #expect(!LoaderRule.shouldDrop(.deploy, from: .awaitingApproval, latest: approved, elapsed: 3))
        #expect(LoaderRule.shouldDrop(.deploy, from: .awaitingApproval, latest: applying, elapsed: 3))
        #expect(LoaderRule.shouldDrop(.deploy, from: .awaitingApproval, latest: approved, elapsed: LoaderRule.cap))
    }

    @Test func runStoreDropsStartedLoaderOnceTargetsMove() throws {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let store = RunStore(deploymentID: "dep_1", loader: .generate, now: start)
        store.accept(try deployment("dep_1", "running", targets: [F.target("tgt_aws", state: "waiting", step: "generate", stepState: "waiting")]),
                     now: start.addingTimeInterval(1))
        #expect(store.pendingLoader == .generate)
        store.accept(try deployment("dep_1", "running", targets: [F.target("tgt_aws", state: "generating", step: "generate", stepState: "running")]),
                     now: start.addingTimeInterval(2))
        #expect(store.pendingLoader == nil)

        // 응답이 오지 않아도 상한이 지나면 내려요
        let stuck = RunStore(deploymentID: "dep_2", loader: .generate, now: start)
        stuck.expireLoader(now: start.addingTimeInterval(1))
        #expect(stuck.pendingLoader == .generate)
        stuck.expireLoader(now: start.addingTimeInterval(LoaderRule.cap))
        #expect(stuck.pendingLoader == nil)
    }

    // MARK: D2 배포 탭이 보여줄 배포

    @Test func deploymentsTabFollowsLatestActive() throws {
        let latest = try deployment("dep_2", "running")
        let older = try deployment("dep_1", "succeeded")
        #expect(DeploymentsFocus(list: [latest, older], displayed: nil, requested: nil) == .init(shown: "dep_2", newer: nil))
        // 끝난 배포만 있으면 없음
        #expect(DeploymentsFocus(list: [older], displayed: nil, requested: nil).shown == nil)
        // 지켜보던 배포가 끝나면 결과를 계속 보여줘요
        #expect(DeploymentsFocus(list: [older], displayed: "dep_1", requested: nil).shown == "dep_1")
        // 보던 배포가 진행 · 결과 화면이면 더 새 배포로 바로 넘어가요
        #expect(DeploymentsFocus(list: [latest, older], displayed: "dep_1", requested: nil) == .init(shown: "dep_2", newer: nil))
    }

    /// 승인 화면에서 삭제 확인을 입력하는 중에 다른 기기에서 새 배포 → 화면을 바꾸지 않고 배너
    @Test func approvalScreenIsNotYanked() throws {
        let newer = try deployment("dep_2", "running")
        let approving = try deployment("dep_1", "awaiting_approval")
        let focus = DeploymentsFocus(list: [newer, approving], displayed: "dep_1", requested: nil)
        #expect(focus == .init(shown: "dep_1", newer: "dep_2"))
        // "보기"를 누르면 새 배포로
        #expect(DeploymentsFocus(list: [newer, approving], displayed: "dep_2", requested: nil) == .init(shown: "dep_2", newer: nil))
    }

    @Test func justStartedDeploymentShowsBeforeListCatchesUp() throws {
        let old = try deployment("dep_1", "running")
        #expect(DeploymentsFocus(list: [old], displayed: "dep_1", requested: "dep_9") == .init(shown: "dep_9", newer: nil))
        // 목록이 따라오면 그대로 가장 최근 배포예요
        let started = try deployment("dep_9", "queued")
        #expect(DeploymentsFocus(list: [started, old], displayed: "dep_1", requested: "dep_9") == .init(shown: "dep_9", newer: nil))
    }

    /// 프로젝트를 바꿔 목록에서 사라진 배포는 붙잡지 않아요
    @Test func displayedFromAnotherProjectIsDropped() throws {
        let other = try deployment("dep_7", "succeeded")
        #expect(DeploymentsFocus(list: [other], displayed: "dep_1", requested: nil).shown == nil)
        #expect(DeploymentsFocus(list: [], displayed: "dep_1", requested: nil).shown == nil)
    }

    // MARK: D12 · P5 같은 배포 화면을 두 번 쌓지 않기

    @Test func deploymentsRootAdoptsDuplicateRunScreens() {
        #expect(RunNavigation.adoption(of: [.started("dep_9")], rootShows: "dep_1")
                == .init(deploymentID: "dep_9", loader: .generate))
        // 알림 · 승인 뒤 배포 화면: 루트가 이미 보여주면 경로를 비워요
        #expect(RunNavigation.adoption(of: [.plan("dep_1"), .run("dep_1")], rootShows: "dep_1")
                == .init(deploymentID: "dep_1", loader: nil))
        // 루트와 다른 배포(예: 완료 알림으로 연 예전 배포)는 그대로 둬요
        #expect(RunNavigation.adoption(of: [.run("dep_0")], rootShows: "dep_1") == nil)
        #expect(RunNavigation.adoption(of: [.logs(deploymentID: "dep_1", targetID: nil)], rootShows: "dep_1") == nil)
        #expect(RunNavigation.adoption(of: [], rootShows: "dep_1") == nil)
    }

    @Test func retryReplacesSourceScreen() {
        // 이력 탭: 결과 화면에서 다시 시도 → 바꿔 끼워요 (같은 화면 두 장 · 채널 두 개가 생기지 않게)
        #expect(RunNavigation.afterRetry([.run("dep_1")], started: "dep_2", source: "dep_1") == [.started("dep_2")])
        #expect(RunNavigation.afterRetry([.started("dep_1")], started: "dep_2", source: "dep_1") == [.started("dep_2")])
        // 원래 배포 화면이 맨 위가 아니면 위에 열어요
        #expect(RunNavigation.afterRetry([], started: "dep_2", source: "dep_1") == [.started("dep_2")])
        #expect(RunNavigation.afterRetry([.logs(deploymentID: "dep_1", targetID: nil)], started: "dep_2", source: "dep_1")
                == [.logs(deploymentID: "dep_1", targetID: nil), .started("dep_2")])
    }

    // MARK: A1 – A3 승인 화면

    /// 배포 화면 안 승인 화면이 처음 값에 머물지 않아요: 승인 상태가 바뀌면 plan을 다시 받아요
    @Test func approvalStoreAcceptsNewDeployment() throws {
        let first = try deployment("dep_1", "awaiting_approval", targets: [approvalTarget("tgt_aws", approval: "pending")],
                                   extra: pending([("tgt_aws", "apr_1")]))
        let store = PlanApprovalStore(deploymentID: "dep_1", deployment: first)
        // 같은 값이면 다시 받지 않아요
        #expect(!store.accept(first))
        // 웹에서 승인 → approval_state가 바뀌어요
        let approvedElsewhere = try deployment("dep_1", "awaiting_approval", targets: [approvalTarget("tgt_aws", approval: "approved")])
        #expect(store.accept(approvedElsewhere))
        #expect(store.deployment == approvedElsewhere)
        // plan.stale → 새 승인 ID
        let regenerated = try deployment("dep_1", "awaiting_approval", targets: [approvalTarget("tgt_aws", approval: "pending")],
                                         extra: pending([("tgt_aws", "apr_2")]))
        #expect(store.accept(regenerated))
        #expect(store.deployment?.approvalItems(for: ["tgt_aws"]).first?.approvalId == "apr_2")
        // 입력하던 삭제 확인 문구는 그대로예요
        store.confirmText = "unibloom"
        _ = store.accept(first)
        #expect(store.confirmText == "unibloom")
    }

    @Test func approvalPhaseFollowsDeployment() throws {
        let waiting = try deployment("dep_1", "awaiting_approval", targets: [approvalTarget("tgt_aws", approval: "pending")])
        #expect(ApprovalPhase(deployment: waiting, approvable: 1, approvedWaiting: 0) == .approvable)
        #expect(ApprovalPhase(deployment: waiting, approvable: 0, approvedWaiting: 1) == .approvedWaiting)
        // 승인할 환경이 남지 않으면 승인 바(→ 409) 대신 안내
        #expect(ApprovalPhase(deployment: waiting, approvable: 0, approvedWaiting: 0) == .nothing)
        // apply가 시작되거나 끝나면 따로 연 승인 화면은 배포 화면으로 넘어가요 (A3)
        let applying = try deployment("dep_1", "running", targets: [F.target("tgt_aws", state: "applying", step: "apply", stepState: "running")])
        #expect(ApprovalPhase(deployment: applying, approvable: 1, approvedWaiting: 0) == .movedOn)
        #expect(ApprovalPhase(deployment: try deployment("dep_1", "cancelled"), approvable: 0, approvedWaiting: 0) == .movedOn)
        // 배포를 아직 모르면 plan만으로 판단해요
        #expect(ApprovalPhase(deployment: nil, approvable: 1, approvedWaiting: 0) == .approvable)
    }
}
