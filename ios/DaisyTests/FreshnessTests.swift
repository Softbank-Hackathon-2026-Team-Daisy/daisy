import Foundation
import Testing
@testable import Daisy

/// 10/3 신선도 검수 ②: 맥락이 바뀌면 이전 데이터 버리기 · 늦은 응답 버리기 · 갱신 실패 표시 (`ScopedState`),
/// "결정이 필요한 배포" 규칙 (`DecisionRule`, O1 · H4), 개요 할 일 · 최근 실행을 한 응답에서 (O4), 이력 더 보기 (H5).
@MainActor
struct FreshnessTests {
    private let t0 = Date(timeIntervalSince1970: 1_790_000_000)

    // MARK: 맥락 · 늦은 응답

    @Test func changingScopeDropsPreviousData() {
        var state = ScopedState<[String]>()
        let first = state.begin("prj_a")
        state.succeed(["a1"], scope: "prj_a", generation: first, at: t0)
        #expect(state.value(for: "prj_a") == ["a1"])

        // 프로젝트를 바꾸면 이전 프로젝트 데이터를 보여주지 않고 로딩부터
        _ = state.begin("prj_b")
        #expect(state.value(for: "prj_b") == nil)
        #expect(state.value(for: "prj_a") == nil)
        if case .loading = state.state(for: "prj_b") {} else { Issue.record("expected loading") }
        #expect(state.staleSince == nil)
    }

    @Test func lateResponseFromPreviousScopeIsDiscarded() {
        var state = ScopedState<[String]>()
        let old = state.begin("prj_a")
        let new = state.begin("prj_b")
        // 이전 프로젝트 요청이 늦게 와도 반영하지 않아요
        let applied1 = state.succeed(["a1"], scope: "prj_a", generation: old)
        #expect(!applied1)
        let applied2 = state.fail("x", scope: "prj_a", generation: old)
        #expect(!applied2)
        #expect(state.value(for: "prj_b") == nil)
        let applied3 = state.succeed(["b1"], scope: "prj_b", generation: new)
        #expect(applied3)
        #expect(state.value(for: "prj_b") == ["b1"])
    }

    /// 같은 맥락으로 다시 돌아와도(A → B → A) 처음 A 요청의 늦은 응답은 버려요
    @Test func lateResponseAfterReturningToSameScopeIsDiscarded() {
        var state = ScopedState<[String]>()
        let stale = state.begin("prj_a")
        _ = state.begin("prj_b")
        let fresh = state.begin("prj_a")
        let applied4 = state.succeed(["old"], scope: "prj_a", generation: stale)
        #expect(!applied4)
        let applied5 = state.succeed(["new"], scope: "prj_a", generation: fresh)
        #expect(applied5)
        #expect(state.value(for: "prj_a") == ["new"])
    }

    /// 같은 맥락에서 먼저 보낸 요청이 나중 요청보다 늦게 오면 버려요 (AI 사용량 배포 빨리 바꾸기 · 새로 고침 연타, AI3)
    @Test func olderRequestInSameScopeDoesNotOverwriteNewer() {
        var state = ScopedState<String>()
        let first = state.begin("prj_a/dep_1")
        let second = state.begin("prj_a/dep_1")
        let applied6 = state.succeed("newer", scope: "prj_a/dep_1", generation: second)
        #expect(applied6)
        let applied7 = state.succeed("older", scope: "prj_a/dep_1", generation: first)
        #expect(!applied7)
        #expect(state.value(for: "prj_a/dep_1") == "newer")
    }

    // MARK: 갱신 실패 표시

    @Test func refreshFailureKeepsDataAndMarksStale() {
        var state = ScopedState<[String]>()
        state.succeed(["a1"], scope: "prj_a", generation: state.begin("prj_a"), at: t0)
        #expect(state.staleSince == nil)

        state.fail("offline", scope: "prj_a", generation: state.begin("prj_a"), at: t0.addingTimeInterval(60))
        #expect(state.value(for: "prj_a") == ["a1"])          // 데이터는 그대로
        #expect(state.staleSince == t0)                         // "마지막 HH:mm"은 마지막 성공 시각

        state.succeed(["a2"], scope: "prj_a", generation: state.begin("prj_a"), at: t0.addingTimeInterval(120))
        #expect(state.staleSince == nil)
        #expect(state.value(for: "prj_a") == ["a2"])
    }

    @Test func firstFailureShowsError() {
        var state = ScopedState<[String]>()
        state.fail("offline", scope: "prj_a", generation: state.begin("prj_a"))
        if case .failed(let message) = state.state(for: "prj_a") { #expect(message == "offline") } else { Issue.record("expected failed") }
        #expect(state.staleSince == nil)
    }

    @Test func staleBannerText() {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = .current
        let date = utc.date(from: DateComponents(year: 2026, month: 10, day: 3, hour: 21, minute: 10))!
        #expect(StaleBanner.text(date) == "갱신하지 못했어요 · 마지막 21:10")
        AppLanguage.$override.withValue(.english) {
            #expect(StaleBanner.text(date) == "Couldn't refresh · last updated 21:10")
        }
    }

    @Test func cancellationIsNotAnError() {
        #expect(Freshness.isCancellation(CancellationError()))
        #expect(Freshness.isCancellation(URLError(.cancelled)))
        #expect(Freshness.isCancellation(APIError.transport(URLError(.cancelled).localizedDescription)))
        #expect(!Freshness.isCancellation(APIError.transport("offline")))
        #expect(!Freshness.isCancellation(APIError.server(status: 401, code: "UNAUTHENTICATED", message: "", retryable: false)))
    }

    @Test func activeDeploymentsPollFasterEvenWhileLive() {
        #expect(Freshness.pollSeconds(live: true, active: false) == PollInterval.whileLive)
        #expect(Freshness.pollSeconds(live: true, active: true) == PollInterval.normal)
        #expect(Freshness.pollSeconds(live: false, active: true) == PollInterval.whileActive)
        #expect(Freshness.pollSeconds(live: false, active: false) == PollInterval.normal)
    }

    // MARK: 결정이 필요한 배포 (O1 · H4)

    private func target(_ id: String, state: String, approval: String? = nil) -> String {
        let approvalField = approval.map { #", "approval_state": "\#($0)""# } ?? ""
        return #"{ "target_id": "\#(id)", "state": "\#(state)", "step": "risk_check", "step_state": "done", "attempt": 1\#(approvalField) }"#
    }

    private func deployment(_ id: String, _ state: String, targets: [String]? = nil) throws -> Deployment {
        let targetsField = targets.map { #", "targets": [\#($0.joined(separator: ","))]"# } ?? ""
        let json = #"{ "id": "\#(id)", "project_id": "prj_1", "commit": "a1b2c3d", "state": "\#(state)"\#(targetsField) }"#
        return try JSONDecoder.daisy.decode(Deployment.self, from: Data(json.utf8))
    }

    @Test func newestWithUnapprovedTargetNeedsDecision() throws {
        let list = [
            try deployment("dep_2", "awaiting_approval", targets: [
                target("tgt_aws", state: "awaiting_approval", approval: "approved"),
                target("tgt_gcp", state: "awaiting_approval", approval: "pending"),
            ]),
            try deployment("dep_1", "succeeded"),
        ]
        #expect(DecisionRule.needingDecision(in: list)?.id == "dep_2")
        #expect(DecisionRule.status(of: list[0], newestID: "dep_2") == .needsDecision)
    }

    /// PR #124 뒤 "진행 중 없음"인데 배지 1: 이미 승인하고 apply만 기다리는 배포는 할 일이 아니에요
    @Test func approvedWaitingIsNotADecision() throws {
        let list = [try deployment("dep_2", "awaiting_approval", targets: [
            target("tgt_aws", state: "awaiting_approval", approval: "approved"),
        ])]
        #expect(DecisionRule.needingDecision(in: list) == nil)
        #expect(DecisionRule.status(of: list[0], newestID: "dep_2") == .approvedWaiting)
        #expect(list[0].listBadge(newestID: "dep_2").text == "승인 완료 · 실행 대기")
    }

    /// 더 새 배포가 생긴 뒤 승인 대기로 남은 배포는 버려진 배포예요: 할 일 · "승인하기" 없음
    @Test func olderAwaitingDeploymentIsAbandoned() throws {
        let list = [
            try deployment("dep_3", "succeeded"),
            try deployment("dep_2", "awaiting_approval", targets: [target("tgt_aws", state: "awaiting_approval", approval: "pending")]),
        ]
        #expect(DecisionRule.needingDecision(in: list) == nil)
        #expect(DecisionRule.status(of: list[1], newestID: "dep_3") == .abandoned)
        #expect(list[1].listBadge(newestID: "dep_3").text == "승인 대기 (지난 배포)")
        #expect(DecisionRule.status(of: list[0], newestID: "dep_3") == .none)
    }

    /// 목록에 환경이 안 오면 배포 상태로 판단해요
    @Test func withoutTargetsFallsBackToDeploymentState() throws {
        #expect(DecisionRule.needingDecision(in: [try deployment("dep_1", "awaiting_approval")])?.id == "dep_1")
        #expect(DecisionRule.needingDecision(in: [try deployment("dep_1", "running")]) == nil)
        #expect(DecisionRule.needingDecision(in: []) == nil)
    }

    // MARK: 개요 한 응답 (O4)

    @Test func overviewBoardComesFromOneResponse() throws {
        let list = [
            try deployment("dep_5", "awaiting_approval", targets: [target("tgt_aws", state: "awaiting_approval", approval: "pending")]),
            try deployment("dep_4", "succeeded"),
            try deployment("dep_3", "awaiting_approval", targets: [target("tgt_aws", state: "awaiting_approval", approval: "pending")]),
            try deployment("dep_2", "failed"),
            try deployment("dep_1", "succeeded"),
        ]
        let board = OverviewStore.Board(list)
        #expect(board.todo?.id == "dep_5")
        #expect(board.recent.map(\.id) == ["dep_4", "dep_3", "dep_2"])   // 할 일로 보여준 배포만 빼요
        #expect(board.newestID == "dep_5")

        let quiet = OverviewStore.Board(Array(list.dropFirst()))
        #expect(quiet.todo == nil)                                       // 지난 승인 대기(dep_3)는 할 일이 아니에요
        #expect(quiet.recent.map(\.id) == ["dep_4", "dep_3", "dep_2"])
    }

    // MARK: 이력 더 보기 (H5)

    @Test func historyLoadMoreAndRefreshKeepOlderPages() throws {
        let first = Page(items: [try deployment("dep_4", "succeeded"), try deployment("dep_3", "failed")], nextCursor: "c1")
        var listing = DeploymentListing.refreshed(nil, first: first)
        #expect(listing.items.map(\.id) == ["dep_4", "dep_3"])
        #expect(listing.nextCursor == "c1")

        listing = listing.appending(Page(items: [try deployment("dep_3", "failed"), try deployment("dep_2", "succeeded")], nextCursor: nil))
        #expect(listing.items.map(\.id) == ["dep_4", "dep_3", "dep_2"])   // 겹친 배포는 한 번만
        #expect(listing.nextCursor == nil)

        // 새 배포가 생긴 뒤 첫 페이지를 다시 받아도 더 받은 지난 배포는 남아요
        let refreshed = DeploymentListing.refreshed(listing, first: Page(items: [try deployment("dep_5", "running"), try deployment("dep_4", "succeeded")], nextCursor: "c2"))
        #expect(refreshed.items.map(\.id) == ["dep_5", "dep_4", "dep_3", "dep_2"])
        #expect(refreshed.nextCursor == nil)

        // 더 받은 적이 없으면 첫 페이지 그대로
        let plain = DeploymentListing.refreshed(DeploymentListing.refreshed(nil, first: first), first: Page(items: [try deployment("dep_5", "running")], nextCursor: "c9"))
        #expect(plain.items.map(\.id) == ["dep_5"])
        #expect(plain.nextCursor == "c9")
    }
}
