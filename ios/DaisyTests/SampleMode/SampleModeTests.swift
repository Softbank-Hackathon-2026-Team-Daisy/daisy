import Foundation
import Testing
@testable import Daisy

/// 예시 데이터 모드 (`Daisy/SampleMode/`). 근거: UI · UX 확인용이라 서버 계약과 같은 모양으로 실제 생길 수 있는 모든 경우를
/// 담아야 하고, 실서버에는 절대 연결하지 않아야 해요. 예시 데이터 모드를 없앨 때 이 폴더도 같이 지워요.
struct SampleModeTests {
    private let routes = SampleFixtures.load()

    private func body(_ key: String) throws -> Data {
        let response = try #require(routes[key], "예시 데이터에 \(key)가 없어요")
        #expect((200..<300).contains(response.status), "\(key)는 성공 응답이어야 해요")
        return response.body
    }

    private func decode<T: Decodable>(_ type: T.Type, _ key: String) throws -> T {
        try JSONDecoder.daisy.decode(type, from: try body(key))
    }

    private var projectIDs: [String] { ["prj_monolith", "prj_msa", "prj_fresh"] }

    private func deployments() throws -> [Deployment] {
        try projectIDs.flatMap { try decode(Page<Deployment>.self, "GET projects/\($0)/deployments").items }
    }

    /// 앱이 읽는 모든 GET 경로가 앱 모델로 그대로 읽혀요
    @Test func everyRouteDecodes() throws {
        let projects = try decode(Page<Project>.self, "GET projects").items
        #expect(projects.map(\.id) == ["prj_monolith", "prj_msa", "prj_fresh", "prj_errors"])
        for id in projectIDs {
            _ = try decode(ProjectDetail.self, "GET projects/\(id)")
            _ = try decode(Page<DeployTarget>.self, "GET projects/\(id)/targets")
            _ = try decode(Page<TargetStatus>.self, "GET projects/\(id)/targets/status")
            _ = try decode(Page<Build>.self, "GET projects/\(id)/builds")
            _ = try decode(Page<Script>.self, "GET projects/\(id)/scripts")
            _ = try decode(Page<AIUsage.Call>.self, "GET projects/\(id)/ai-usage")
        }
        _ = try decode(Page<Build>.self, "GET projects/prj_monolith/builds?cursor=eyJ0IjoiMjAyNi0xMC0wMlQwMjo0OTo1N1oiLCJpZCI6InN2X21fMDQifQ")
        _ = try decode(ProjectDetail.self, "GET projects/prj_errors")
        let all = try deployments()
        #expect(all.count == 12)
        for deployment in all {
            let d = "deployments/\(deployment.id)"
            let detail = try decode(Deployment.self, "GET \(d)")
            #expect(detail == deployment, "목록과 상세가 같아야 해요: \(deployment.id)")
            let plan = try decode(Plan.self, "GET \(d)/plan")
            let details = try decode([PlanDetail].self, "GET \(d)/plan?detail=resources")
            #expect(Set(details.map(\.targetId)) == Set(plan.targets.map(\.targetId)))
            _ = try decode(Page<LogLine>.self, "GET \(d)/logs")
        }
        let connected = try decode(ConnectResult.self, "POST projects")
        #expect(connected.project.id == "prj_fresh" && connected.manifest == nil)
    }

    /// 서버 계약에 있는 값이 모두 한 번 이상 나와요 (실제 생길 수 있는 모든 경우). 값 목록은 서버 enum · DB 제약(10/2 OpenAPI) 그대로예요
    @Test func coversEveryServerValue() throws {
        let all = try deployments()
        let targets = all.flatMap { $0.targets ?? [] }
        #expect(Set(all.map(\.state)) == [.queued, .running, .awaitingApproval, .succeeded, .partiallySucceeded, .failed, .cancelled])
        #expect(Set(targets.compactMap(\.state)) == [.waiting, .generating, .validating, .awaitingApproval, .applying, .verifying, .succeeded, .failed, .cancelled])
        #expect(Set(targets.map(\.step)) == [.generate, .validate, .plan, .riskCheck, .apply, .healthCheck, .unknown])   // null → unknown
        #expect(Set(targets.map(\.stepState)) == [.running, .done, .failed, .unknown])          // 서버는 waiting · skipped를 보내지 않아요
        #expect(Set(targets.compactMap(\.approvalState)) == [.pending, .approved, .rejected, .superseded, .expired])
        #expect(targets.contains { $0.approvalState == nil })
        #expect(Set(targets.compactMap(\.applyDispatch)) == ["queued", "unknown", "rejected"])
        #expect(Set(targets.map(\.attempt)) == [0, 1, 2, 3])                                     // null → 0
        #expect(targets.contains { $0.errorSummary == "dispatch_rejected" })
        #expect(targets.contains { $0.reusedScript == true } && targets.contains { $0.isApprovedWaiting })
        #expect(all.contains { $0.isRollback })
        #expect(all.contains { !($0.pendingApprovals ?? []).isEmpty })

        let statuses = try projectIDs.flatMap { try decode(Page<TargetStatus>.self, "GET projects/\($0)/targets/status").items }
        #expect(Set(statuses.compactMap(\.currentStatus)) == [.none, .confirmed, .unverified])
        #expect(Set(statuses.map(\.health)) == [.healthy, .unhealthy, .unknown])
        let targetsList = try projectIDs.flatMap { try decode(Page<DeployTarget>.self, "GET projects/\($0)/targets").items }
        #expect(Set(targetsList.compactMap(\.connection?.state)) == [.ok, .failed, .unknown])
        #expect(Set(targetsList.map(\.type)) == [.onprem, .aws, .gcp, .azure])
        #expect(targetsList.contains { $0.reuse == nil } && targetsList.contains { $0.runtime == nil })

        let builds = try projectIDs.flatMap { try decode(Page<Build>.self, "GET projects/\($0)/builds").items }
        #expect(Set(builds.map(\.pipeline.status)) == [.queued, .running, .success, .failed])
        let scripts = try projectIDs.flatMap { try decode(Page<Script>.self, "GET projects/\($0)/scripts").items }
        #expect(Set(scripts.map(\.origin)) == [.aiGenerated, .reused, nil])
        #expect(Set(scripts.map(\.status)) == [.verified, .discarded])
        let resources = try all.flatMap { try decode([PlanDetail].self, "GET deployments/\($0.id)/plan?detail=resources") }
            .flatMap { $0.resources ?? [] }
        #expect(Set(resources.map(\.action)) == [.create, .update, .delete, .replace])
        let risks = try all.flatMap { try decode(Plan.self, "GET deployments/\($0.id)/plan").targets.flatMap(\.risks) }
        #expect(Set(risks.map(\.level)) == [.high, .medium, .low])
        let calls = try decode(Page<AIUsage.Call>.self, "GET projects/prj_monolith/ai-usage").items
        #expect(Set(calls.map(\.step)) == [.generate, .fix] && Set(calls.map(\.status)) == [.succeeded, .failed, .unknown])
        #expect(calls.contains { $0.tokens == nil })
        let logs = try all.flatMap { try decode(Page<LogLine>.self, "GET deployments/\($0.id)/logs").items }
        #expect(Set(logs.map(\.level)) == ["debug", "info", "warn", "error"])
        #expect(logs.contains { $0.targetId == nil } && logs.contains { $0.text.isEmpty })

        // 앱이 아직 읽지 않는 서버 필드도 서버 모양 그대로 있어요: 다시 시도(retry_of), 서비스 여럿(images)
        let raw = try JSONSerialization.jsonObject(with: try body("GET projects/prj_monolith/deployments")) as? [String: Any]
        let rows = try #require(raw?["items"] as? [[String: Any]])
        #expect(rows.contains { $0["retry_of"] is String })
        #expect(rows.allSatisfy { $0.keys.contains("retry_of") && $0.keys.contains("last_seq") })
        let msa = try JSONSerialization.jsonObject(with: try body("GET deployments/dep_s_01")) as? [String: Any]
        #expect((msa?["images"] as? [Any])?.count == 2 && msa?["image"] is NSNull)
    }

    /// 서버에 없는 요청은 실서버처럼 404예요 (manifest · 배포별 스크립트 · 리소스 · 연결 테스트)
    @Test func missingServerRoutesAre404() {
        for (method, path) in [("GET", "projects/prj_monolith/manifest"), ("GET", "deployments/dep_m_03/targets/tgt_demo_aws/script"),
                               ("GET", "targets/tgt_demo_aws/resources"), ("POST", "targets/tgt_demo_aws/test")] {
            let response = SampleFixtures.respond(method: method, path: path, query: [], role: "owner")
            #expect(response.status == 404)
        }
    }

    /// 실패 응답은 서버 오류 봉투 모양이고, 코드는 서버 ErrorCode 중 하나예요
    @Test func errorsUseServerEnvelope() throws {
        let codes: Set = ["VALIDATION_FAILED", "UNAUTHENTICATED", "FORBIDDEN", "NOT_FOUND", "TARGET_LOCKED", "STATE_CONFLICT", "MANIFEST_INVALID", "RATE_LIMITED", "INTERNAL"]
        let failures = routes.filter { !(200..<300).contains($0.value.status) }
        #expect(failures.count >= 10)
        for (key, response) in failures {
            let root = try #require(try JSONSerialization.jsonObject(with: response.body) as? [String: Any], "\(key)")
            let error = try #require(root["error"] as? [String: Any], "\(key)")
            #expect(codes.contains(error["code"] as? String ?? ""), "\(key)")
            #expect(error["details"] is [String: Any] && error["retryable"] is Bool && error["message"] is String, "\(key)")
        }
    }

    /// 실서버에는 절대 연결하지 않아요: 예시 세션은 주소와 상관없이 모든 요청을 번들로 답해요
    @Test func neverReachesTheNetwork() async throws {
        #expect(SampleModeProtocol.canInit(with: URLRequest(url: URL(string: "https://api.unibloom.cloud/projects")!)))
        #expect(SampleMode.session.configuration.protocolClasses?.first == SampleModeProtocol.self)
        let client = try #require(SampleMode.client(token: SampleMode.token(role: "owner")))
        #expect(client.baseURL.host() == "sample-mode.invalid")
        // 실서버 주소로 보내도 번들이 답해요
        let real = APIClient(baseURL: URL(string: "https://api.unibloom.cloud")!, token: SampleMode.token(role: "owner"), session: SampleMode.session)
        let projects = try await real.send(.projects()).items
        #expect(projects.count == 4)
        #expect(SampleMode.client(token: "real-token") == nil)
    }

    /// 쓰기: 팀 계정은 서버 응답 모양 그대로 받고, 읽기 전용 계정은 실서버처럼 403이에요
    @Test func writesFollowRole() async throws {
        let owner = try #require(SampleMode.client(token: SampleMode.token(role: "owner")))
        let created = try await owner.send(.startDeployment(projectID: "prj_monolith", commit: "5139b93e8a4f2c71d0b6e9a3c5f8172d4e6b0a91",
                                                            sourceVersionID: "sv_m_06", targetIDs: ["tgt_demo_aws"]))
        #expect(created.id == "dep_m_01" && created.state == .queued)
        _ = try await owner.send(.approve(deploymentID: "dep_m_03", decision: .approve,
                                          items: [.init(targetId: "tgt_demo_aws", approvalId: "apv_m03_aws")]))
        let waiting = try await owner.send(.deployments(projectID: "prj_monolith", state: .awaitingApproval)).items
        #expect(!waiting.isEmpty && waiting.allSatisfy { $0.state == .awaitingApproval })

        let viewer = try #require(SampleMode.client(token: SampleMode.token(role: "viewer")))
        do {
            _ = try await viewer.send(.approve(deploymentID: "dep_m_03", decision: .approve,
                                               items: [.init(targetId: "tgt_demo_aws", approvalId: "apv_m03_aws")]))
            Issue.record("읽기 전용 계정의 승인이 통과하면 안 돼요")
        } catch let APIError.server(status, code, _, _) {
            #expect(status == 403 && code == "FORBIDDEN")
        }
    }

    /// 앱을 언제 열어도 가장 최근 배포가 몇 분 전이에요
    @Test func datesFollowLaunchTime() throws {
        let later = Date.now.addingTimeInterval(60 * 60 * 24 * 30)
        let shifted = SampleFixtures.load(now: later)
        let body = try #require(shifted["GET projects/prj_monolith/deployments"]?.body)
        let newest = try #require(try JSONDecoder.daisy.decode(Page<Deployment>.self, from: body).items.compactMap(\.createdAt).max())
        #expect(later.timeIntervalSince(newest) > 0 && later.timeIntervalSince(newest) < 5 * 60)
        // 소수 초 자릿수는 그대로예요 (서버는 마이크로초를 보내요)
        let anchorPlusHour = try Date("2026-10-02T15:00:00Z", strategy: .iso8601)
        let moved = SampleFixtures.shiftDates(in: #"{"anchor": "2026-10-02T14:00:00Z", "at": "2026-10-02T13:00:00.123456Z"}"#, now: anchorPlusHour)
        #expect(moved.contains("2026-10-02T14:00:00.123456Z"))
    }

    /// 로그인 화면에서만 들어가고, 토큰을 저장하지 않아서 앱을 다시 켜면 로그인 화면이에요
    @Test @MainActor func appModelEntersAndLeaves() {
        let suite = "SampleModeTests-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = TokenStore(service: suite)
        let app = AppModel(tokenStore: store, defaults: defaults)
        app.enterSampleMode(role: "viewer")
        #expect(app.isSampleMode && app.isSignedIn && app.isViewer)
        #expect(app.client?.baseURL.host() == "sample-mode.invalid")
        #expect(AppModel(tokenStore: store, defaults: defaults).isSignedIn == false)
        app.signOut()
        #expect(!app.isSampleMode && !app.isSignedIn)
        app.enterSampleMode(role: "owner")
        #expect(app.isSampleMode && !app.isViewer)
    }

    /// 이름("예시 데이터")은 고른 언어로 보여요. 문구는 예시 모드 문구표에만 있어요
    @Test @MainActor func displayNameFollowsLanguage() {
        let suite = "SampleModeTests-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let app = AppModel(tokenStore: TokenStore(service: suite), defaults: defaults)
        app.enterSampleMode(role: "owner")
        AppLanguage.$override.withValue(.korean) { #expect(app.displayName == "예시 데이터") }
        AppLanguage.$override.withValue(.english) { #expect(app.displayName == "Sample data") }
        AppLanguage.$override.withValue(.japanese) { #expect(app.displayName == "サンプルデータ") }
    }
}
