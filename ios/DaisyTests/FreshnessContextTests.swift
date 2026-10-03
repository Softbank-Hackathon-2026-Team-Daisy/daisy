import Foundation
import Synchronization
import Testing
@testable import Daisy

/// 데이터 신선도 (10/3 검수표 ①): 계정 · 프로젝트가 바뀌면 이전 데이터 · 화면이 남지 않는지, 늦게 온 응답을 버리는지,
/// 배지 기준, 취소된 요청, SSE 403 · 404 재시도, 앱 활성화 신호를 봐요. 네트워크는 쓰지 않아요 (`ScriptedAPI`).
struct FreshnessContextTests {
    // MARK: 맥락 초기화 (L1 · L2 · P3)

    /// 로그아웃하면 Workspace · Router · 고른 프로젝트 · 이름 · 열려던 알림이 모두 비워져요
    @Test @MainActor func signOutResetsWorkspaceRouterAndSelection() async throws {
        let api = ScriptedAPI.Account()
        api.standardProject()
        let (app, workspace, router) = api.boundApp()
        await workspace.refresh(using: app)
        #expect(app.selectedProjectID == "prj_1")
        #expect(!workspace.projects.isEmpty && !workspace.statuses.isEmpty && workspace.actionableApproval != nil)

        router.open(.plan("dep_1"))
        router.tab = .history
        router.push(.run("dep_0"))
        app.push.pendingOpen = PushPayload(kind: .approvalRequired, projectID: "prj_1", deploymentID: "dep_1")

        app.signOut()
        #expect(!app.isSignedIn && app.selectedProjectID == nil && app.username == nil)
        #expect(app.push.pendingOpen == nil)
        #expect(workspace.projects.isEmpty && workspace.statuses.isEmpty && workspace.targets.isEmpty)
        #expect(workspace.recentDeployments.isEmpty && workspace.actionableApproval == nil)
        #expect(!workspace.loadedOnce && workspace.project == nil)
        #expect(router.tab == .overview)
        for tab in AppTab.allCases { #expect(router.path(for: tab).wrappedValue.isEmpty) }
    }

    /// 로그아웃 중 늦게 끝난 refresh는 반영하지 않아요 (다른 계정으로 로그인해도 이전 계정 데이터가 안 보여요)
    @Test @MainActor func refreshFinishingAfterSignOutIsDropped() async throws {
        let api = ScriptedAPI.Account()
        api.standardProject()
        api.set("/projects", .ok(ScriptedAPI.projectsBody, delay: 0.3))
        let (app, workspace, _) = api.boundApp()
        let late = Task { await workspace.refresh(using: app) }
        try await api.waitUntilRequested("/projects")
        app.signOut()
        await late.value
        #expect(workspace.projects.isEmpty && workspace.statuses.isEmpty)
    }

    /// 알림은 로그인돼 있을 때만 열어요 (P3)
    @Test @MainActor func pushIsIgnoredWhileSignedOut() {
        let app = PushFake.appModel()
        let router = Router()
        PushPayload(kind: .approvalRequired, projectID: "prj_2", deploymentID: "dep_9").open(app: app, router: router)
        #expect(app.selectedProjectID == nil)
        #expect(router.path(for: .deployments).wrappedValue.isEmpty)
    }

    // MARK: 프로젝트 전환 (S3 · S4 · S5 · D4 · ST3 · C2)

    /// 프로젝트를 바꾸면 이전 프로젝트 데이터가 바로 비고, 새 이름이 바로 보이고, 모든 메뉴 경로가 비워져요 (연결 흐름만 남아요).
    /// 다시 읽으라는 신호(`live.changes`)도 바로 울려요
    @Test @MainActor func projectChangeClearsDataAndPaths() async throws {
        let api = ScriptedAPI.Account()
        api.standardProject()
        let (app, workspace, router) = api.boundApp()
        await workspace.refresh(using: app)
        router.open(.selectTargets(commit: "abc"))
        router.tab = .history
        router.push(.run("dep_0"))
        router.open(.connectProject)
        #expect(router.tab == .overview)
        #expect(router.path(for: .deployments).wrappedValue == [.selectTargets(commit: "abc")])  // 연결이 배포 경로를 지우지 않아요 (C2)

        let signals = workspace.live.changes.count
        app.selectedProjectID = "prj_2"
        #expect(workspace.project?.name == "two")
        #expect(workspace.statuses.isEmpty && workspace.targets.isEmpty && workspace.actionableApproval == nil)
        #expect(workspace.live.changes.count == signals + 1)
        #expect(router.path(for: .deployments).wrappedValue.isEmpty)
        #expect(router.path(for: .history).wrappedValue.isEmpty)
        #expect(router.path(for: .overview).wrappedValue == [.connectProject])
    }

    /// 전환 직전에 시작한 이전 프로젝트 요청이 늦게 끝나도 새 프로젝트 데이터를 덮어쓰지 않아요 (S4)
    @Test @MainActor func lateResultsForOldProjectAreDiscarded() async throws {
        let api = ScriptedAPI.Account()
        api.standardProject()
        api.set("/projects/prj_1/targets/status", .ok(ScriptedAPI.statuses("tgt_old"), delay: 0.4))
        api.set("/projects/prj_2/targets/status", .ok(ScriptedAPI.statuses("tgt_new")))
        api.set("/projects/prj_2/targets", .ok(#"{"items":[],"next_cursor":null}"#))
        api.set("/projects/prj_2/deployments", .ok(#"{"items":[],"next_cursor":null}"#))
        let (app, workspace, _) = api.boundApp()
        app.selectedProjectID = "prj_1"

        let old = Task { await workspace.refresh(using: app) }
        try await api.waitUntilRequested("/projects/prj_1/targets/status")
        app.selectedProjectID = "prj_2"
        await workspace.refresh(using: app)
        #expect(workspace.statuses.map(\.targetId) == ["tgt_new"])
        await old.value
        #expect(workspace.statuses.map(\.targetId) == ["tgt_new"])
        #expect(workspace.project?.id == "prj_2")
        #expect(workspace.actionableApproval == nil)
    }

    /// 전환 뒤 새 프로젝트 요청이 실패하면 이전 프로젝트 값이 아니라 빈 값이에요 (S3)
    @Test @MainActor func failedRequestsAfterSwitchDoNotShowOldProject() async throws {
        let api = ScriptedAPI.Account()
        api.standardProject()
        api.set("/projects/prj_2/targets/status", .status(500))
        api.set("/projects/prj_2/targets", .status(500))
        api.set("/projects/prj_2/deployments", .status(500))
        let (app, workspace, _) = api.boundApp()
        await workspace.refresh(using: app)
        #expect(!workspace.statuses.isEmpty)
        app.selectedProjectID = "prj_2"
        await workspace.refresh(using: app)
        #expect(workspace.statuses.isEmpty && workspace.targets.isEmpty && workspace.recentDeployments.isEmpty)
    }

    // MARK: 오류 (O5 · X2 · X4)

    /// 승인 대기(A-03) 요청만 실패하면 배지를 지우지 않고 이전 값을 둬요 (O5)
    @Test @MainActor func approvalFailureKeepsPreviousValue() async throws {
        let api = ScriptedAPI.Account()
        api.standardProject()
        let (app, workspace, _) = api.boundApp()
        await workspace.refresh(using: app)
        #expect(workspace.actionableApproval?.id == "dep_1")
        api.set("/projects/prj_1/deployments", .status(500))
        await workspace.refresh(using: app)
        #expect(workspace.actionableApproval?.id == "dep_1")
    }

    /// 프로젝트 데이터 요청의 401을 삼키지 않아요 → 로그아웃 (로그인 화면)
    @Test @MainActor func unauthorizedProjectRequestSignsOut() async throws {
        let api = ScriptedAPI.Account()
        api.standardProject()
        api.set("/projects/prj_1/targets", .status(401))
        let (app, workspace, _) = api.boundApp()
        await workspace.refresh(using: app)
        #expect(!app.isSignedIn && app.sessionExpired)
        #expect(workspace.projects.isEmpty)
    }

    /// 취소된 요청은 실패가 아니에요: `CancellationError`로 오고, 로그아웃 · 오류 표시를 하지 않아요 (X4)
    @Test @MainActor func cancelledRequestsAreNotFailures() async throws {
        let api = ScriptedAPI.Account()
        api.set("/projects", .ok(ScriptedAPI.projectsBody, delay: 5))
        let (app, workspace, _) = api.boundApp()
        let client = try #require(app.client)
        let task = Task { try await client.send(.projects()) }
        try await api.waitUntilRequested("/projects")
        task.cancel()
        let result = await task.result
        #expect(throws: CancellationError.self) { try result.get() }
        #expect(URLError(.cancelled).isCancellation && CancellationError().isCancellation)
        #expect(!APIError.transport("x").isCancellation)
        app.handle(CancellationError())
        #expect(app.isSignedIn)

        // Workspace refresh가 취소되면 연결 표시 · 데이터를 바꾸지 않아요
        let refresh = Task { await workspace.refresh(using: app) }
        try await api.waitUntilRequested("/projects", times: 2)
        refresh.cancel()
        await refresh.value
        #expect(!workspace.loadedOnce && workspace.connection == .reconnecting && app.isSignedIn)
    }

    /// 요청은 URLSession 캐시를 쓰지 않아요 (I3)
    @Test func requestsIgnoreLocalCache() throws {
        let client = APIClient(baseURL: URL(string: "https://api.example.com")!, token: "t")
        #expect(try client.request(for: .projects()).cachePolicy == .reloadIgnoringLocalCacheData)
    }

    // MARK: 배지 기준 (S1)

    @Test func needsDecisionOnlyWhileSomeTargetAwaitsApproval() throws {
        let pending = try Fixture.deployment("awaiting_approval", targets: [
            Fixture.target("tgt_aws", state: "awaiting_approval", step: "risk_check", stepState: "done"),
        ])
        #expect(pending.needsDecision)

        // 승인했고 apply 전(승인 완료 · 실행 대기)이면 아니에요
        let approved = try Fixture.deployment("awaiting_approval", targets: [
            #"{ "target_id": "tgt_aws", "state": "awaiting_approval", "step": "risk_check", "step_state": "done", "approval_state": "approved" }"#,
        ])
        #expect(!approved.needsDecision)

        // 하나는 승인 완료, 하나는 아직이면 맞아요
        let mixed = try Fixture.deployment("awaiting_approval", targets: [
            #"{ "target_id": "tgt_aws", "state": "awaiting_approval", "step": "risk_check", "step_state": "done", "approval_state": "approved" }"#,
            Fixture.target("tgt_gcp", state: "awaiting_approval", step: "risk_check", stepState: "done"),
        ])
        #expect(mixed.needsDecision)

        let running = try Fixture.deployment("running", targets: [
            Fixture.target("tgt_aws", state: "awaiting_approval", step: "risk_check", stepState: "done"),
        ])
        #expect(!running.needsDecision)
    }

    /// 가장 최근 배포만 봐요: 새 배포에 밀린 예전 승인 대기는 배지에 안 들어가요
    @Test @MainActor func badgeLooksOnlyAtLatestDeployment() async throws {
        let api = ScriptedAPI.Account()
        api.standardProject()
        api.set("/projects/prj_1/deployments", .ok("""
        {"items":[\(ScriptedAPI.deployment("dep_2", state: "succeeded")),\(ScriptedAPI.deployment("dep_1", state: "awaiting_approval"))],"next_cursor":null}
        """))
        let (app, workspace, _) = api.boundApp()
        await workspace.refresh(using: app)
        #expect(workspace.latestDeployment?.id == "dep_2")
        #expect(workspace.actionableApproval == nil && workspace.awaitingApproval.isEmpty)
        #expect(!workspace.hasActiveDeployment)
    }

    /// 프로젝트 채널에는 승인 · 상태 이벤트가 없어서 진행 중이면 연결 중에도 5초, 끊기면 2초
    @Test func projectPollingIsFasterWhileActive() {
        #expect(PollInterval.project(live: true, active: true) == 5)
        #expect(PollInterval.project(live: false, active: true) == 2)
        #expect(PollInterval.project(live: true, active: false) == 15)
        #expect(PollInterval.project(live: false, active: false) == 5)
    }

    // MARK: 경로 규칙 (A5 · P2 · C2)

    @Test @MainActor func routerOpenRules() {
        let router = Router()
        router.open(.plan("dep_1"))
        router.push(.run("dep_1"))
        router.open(.run("dep_1"))  // 같은 화면이 맨 위면 그대로
        #expect(router.path(for: .deployments).wrappedValue == [.plan("dep_1"), .run("dep_1")])
        router.open(.plan("dep_2"))  // 다른 화면이면 배포 메뉴를 비우고 열어요
        #expect(router.path(for: .deployments).wrappedValue == [.plan("dep_2")])
        router.open(.connectProject, in: .settings)  // 메뉴를 주면 그 메뉴
        #expect(router.tab == .settings && router.path(for: .deployments).wrappedValue == [.plan("dep_2")])
        router.apply(.account)
        #expect(router.tab == .overview && router.path(for: .deployments).wrappedValue.isEmpty)
    }

    // MARK: 생명주기 (L3) · SSE (I2)

    /// 앱이 앞으로 오면 바로 다시 읽으라는 신호를 주고, 연결이 끊겼거나 오래 뒤에 있었으면 SSE를 다시 열어요
    @Test @MainActor func becomingActiveSignalsReloadAndReconnect() {
        let workspace = Workspace()
        let start = Date(timeIntervalSince1970: 1_000)
        let signals = workspace.live.changes.count
        workspace.sceneDidBecomeActive(now: start)  // 처음 켤 때: 다시 읽기만, 연결은 그대로
        #expect(workspace.live.changes.count == signals + 1 && workspace.reconnects == 0)
        workspace.sceneDidResignActive(now: start)
        workspace.sceneDidBecomeActive(now: start.addingTimeInterval(2))
        #expect(workspace.live.changes.count == signals + 2)
        #expect(workspace.reconnects == 1)  // 연결이 안 붙어 있어서
    }

    /// 403 · 404는 멈추지 않고 길게 쉰 뒤 다시 붙어요. 401만 멈춰요
    @Test func streamRetriesAfterForbiddenOrNotFound() async {
        let token = "sse-\(UUID().uuidString)"
        let api = ScriptedAPI.Account(token: token)
        api.queue("/projects/prj_sse/events", [
            .status(404),
            .status(403),
            .init(status: 200, body: "id:3\nevent:build.received\ndata:{}\n\n", contentType: "text/event-stream"),
            .status(401),
        ])
        var stream = EventStream(baseURL: URL(string: "https://api.example.com")!, token: token, session: ScriptedAPI.session)
        stream.retryDelay = { _ in .zero }
        stream.blockedWait = .zero
        var signals: [RealtimeSignal] = []
        for await signal in stream.subscribe(path: "projects/prj_sse/events") { signals.append(signal) }
        #expect(signals == [
            .state(.disconnected),
            .state(.disconnected),
            .state(.connected),
            .event(ServerEvent(id: 3, event: "build.received", data: "{}")),
            .state(.reconnecting),
            .state(.disconnected),
        ])
    }
}

// MARK: - 테스트 도구

/// 토큰마다 따로 답하는 가짜 서버 (테스트가 동시에 돌아도 섞이지 않게 Bearer 토큰으로 나눠요).
/// 경로마다 고정 응답(`set`) 또는 차례대로 줄 응답(`queue`). 없으면 404예요. 받은 요청 경로를 적어 둬요
final class ScriptedAPI: URLProtocol, @unchecked Sendable {
    struct Reply: Sendable {
        var status = 200
        var body = ""
        var delay: Double = 0
        var contentType = "application/json"

        static func ok(_ body: String, delay: Double = 0) -> Reply { Reply(body: body, delay: delay) }
        static func status(_ code: Int) -> Reply {
            Reply(status: code, body: #"{"error":{"code":"HTTP_\#(code)","message":"x","retryable":false}}"#)
        }
    }

    private static let fixed = Mutex<[String: Reply]>([:])
    private static let queued = Mutex<[String: [Reply]]>([:])
    private static let seen = Mutex<[String]>([])
    private let stopped = Mutex(false)

    static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ScriptedAPI.self]
        return URLSession(configuration: configuration)
    }()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let token = request.value(forHTTPHeaderField: "Authorization")?.replacingOccurrences(of: "Bearer ", with: "") ?? "-"
        let key = "\(token) \(request.url!.path)"
        Self.seen.withLock { $0.append(key) }
        let next = Self.queued.withLock { $0[key]?.isEmpty == false ? $0[key]!.removeFirst() : nil }
        let reply = next ?? Self.fixed.withLock { $0[key] } ?? .status(404)
        let deliver: @Sendable () -> Void = { [self] in
            guard !stopped.withLock({ $0 }) else { return }
            let response = HTTPURLResponse(url: request.url!, statusCode: reply.status, httpVersion: "HTTP/1.1",
                                           headerFields: ["Content-Type": reply.contentType])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(reply.body.utf8))
            client?.urlProtocolDidFinishLoading(self)
        }
        if reply.delay > 0 {
            DispatchQueue.global().asyncAfter(deadline: .now() + reply.delay, execute: deliver)
        } else {
            deliver()
        }
    }

    override func stopLoading() { stopped.withLock { $0 = true } }

    /// 한 테스트의 계정 (토큰 하나)
    struct Account: Sendable {
        var token = "freshness-\(UUID().uuidString)"

        func set(_ path: String, _ reply: Reply) { ScriptedAPI.fixed.withLock { $0["\(token) \(path)"] = reply } }
        func queue(_ path: String, _ replies: [Reply]) { ScriptedAPI.queued.withLock { $0["\(token) \(path)"] = replies } }

        /// 요청이 서버에 닿을 때까지 기다려요 (최대 3초)
        func waitUntilRequested(_ path: String, times: Int = 1) async throws {
            let key = "\(token) \(path)"
            for _ in 0..<300 {
                if ScriptedAPI.seen.withLock({ $0.filter { $0 == key }.count }) >= times { return }
                try await Task.sleep(for: .milliseconds(10))
            }
            Issue.record("요청이 오지 않았어요: \(path)")
        }

        /// 프로젝트 둘(prj_1 · prj_2), prj_1은 환경 하나와 승인 대기 배포 하나
        func standardProject() {
            set("/projects", .ok(ScriptedAPI.projectsBody))
            set("/projects/prj_1/targets/status", .ok(ScriptedAPI.statuses("tgt_aws")))
            set("/projects/prj_1/targets", .ok(#"{"items":[{"target_id":"tgt_aws","type":"aws","name":"aws-1"}],"next_cursor":null}"#))
            set("/projects/prj_1/deployments", .ok(#"{"items":[\#(ScriptedAPI.deployment("dep_1", state: "awaiting_approval"))],"next_cursor":null}"#))
        }

        /// 이 토큰으로 로그인한 AppModel과 묶인 Workspace · Router
        @MainActor func boundApp() -> (AppModel, Workspace, Router) {
            let store = TokenStore(service: "FreshnessTests-\(UUID().uuidString)")
            store.save(token)
            let defaults = UserDefaults(suiteName: "FreshnessTests-\(UUID().uuidString)")!
            let app = AppModel(tokenStore: store, defaults: defaults, push: PushFake().registry, apiSession: ScriptedAPI.session)
            let workspace = Workspace(), router = Router()
            app.bind(workspace: workspace, router: router)
            return (app, workspace, router)
        }
    }

    static let projectsBody = #"{"items":[{"id":"prj_1","name":"one"},{"id":"prj_2","name":"two"}],"next_cursor":null}"#

    static func statuses(_ targetID: String) -> String {
        #"{"items":[{"target_id":"\#(targetID)","type":"aws","name":"aws-1","health":"healthy"}],"next_cursor":null}"#
    }

    static func deployment(_ id: String, state: String) -> String {
        let target = state == "awaiting_approval"
            ? #"{"target_id":"tgt_aws","state":"awaiting_approval","step":"risk_check","step_state":"done","approval_state":"pending"}"#
            : #"{"target_id":"tgt_aws","state":"succeeded","step":"health_check","step_state":"done"}"#
        return #"{"id":"\#(id)","project_id":"prj_1","commit":"abc1234","state":"\#(state)","targets":[\#(target)]}"#
    }
}
