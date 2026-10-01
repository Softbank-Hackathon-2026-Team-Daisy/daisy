import Foundation
import Testing
@testable import Daisy

/// 예시 데이터 번들 (Resources/SampleData/sample.json, scripts/sample-data/generate.py).
/// 근거: 심사 · 발표 때 서버 없이도 모든 화면이 떠야 하고, 쓰기는 막혀야 하고, 늘 최근처럼 보여야 해요.
struct SampleDataTests {
    private let data = SampleData.load()

    private func decode<T: Decodable>(_ type: T.Type, _ path: String) throws -> T {
        let body = try #require(data[path], "예시 데이터에 \(path)가 없어요")
        return try JSONDecoder.daisy.decode(type, from: body)
    }

    /// 앱이 부르는 모든 경로가 번들에 있고, 앱 모델로 그대로 디코딩돼요
    @Test func everyScreenDecodes() throws {
        let projects = try decode(Page<Project>.self, "projects").items
        #expect(projects.map(\.name) == ["sample-monolith", "sample-msa"])
        for project in projects {
            let p = "projects/\(project.id)"
            let deployments = try decode(Page<Deployment>.self, "\(p)/deployments").items
            #expect(!deployments.isEmpty)
            _ = try decode(Page<TargetStatus>.self, "\(p)/targets/status")
            _ = try decode(Page<DeployTarget>.self, "\(p)/targets")
            _ = try decode(Page<Build>.self, "\(p)/builds")
            _ = try decode(Page<Script>.self, "\(p)/scripts")
            _ = try decode(Manifest.self, "\(p)/manifest")
            _ = try decode(ProjectDetail.self, p)
            _ = try decode(Page<AIUsage.Call>.self, "\(p)/ai-usage")
            for deployment in deployments {
                let d = "deployments/\(deployment.id)"
                _ = try decode(Deployment.self, d)
                _ = try decode(Plan.self, "\(d)/plan")
                _ = try decode(Page<LogLine>.self, "\(d)/logs")
                for target in deployment.targets ?? [] {
                    _ = try decode(Script.self, "\(d)/targets/\(target.targetId)/script")
                }
            }
        }
        for target in ["tgt_onprem", "tgt_aws", "tgt_gcp"] {
            _ = try decode(Page<EnvironmentResource>.self, "targets/\(target)/resources")
        }
    }

    /// 발표에서 보여줄 흐름 화면이 전부 들어 있어요 (W-05 · W-05b · W-06 · W-07 · W-08, 일부 성공 포함)
    @Test func coversEveryRunStage() throws {
        let all = try ["prj_monolith", "prj_msa"].flatMap { try decode(Page<Deployment>.self, "projects/\($0)/deployments").items }
        let stages = Set(all.map(RunStage.init))
        #expect(stages == [.generate, .stopped, .approval, .apply, .result])
        #expect(all.contains { $0.state == .partiallySucceeded })
    }

    /// 빌드는 Jenkins로 해요 (9/30 회의: GitHub Actions 대신 Jenkins)
    @Test func buildsRunOnJenkins() throws {
        let detail = try decode(ProjectDetail.self, "projects/prj_monolith")
        #expect(detail.build?.hasPrefix("Jenkins") == true)
        let builds = try decode(Page<Build>.self, "projects/prj_monolith/builds").items
        #expect(builds.allSatisfy { $0.pipeline.runUrl?.host == "jenkins.example.com" })
    }

    /// 커밋은 실제 GitHub sample 레포에서 가져와요 (40자 SHA)
    @Test func usesRealCommits() throws {
        let builds = try decode(Page<Build>.self, "projects/prj_monolith/builds").items
        #expect(builds.count >= 3)
        #expect(builds.allSatisfy { $0.commit.count == 40 && $0.commit.allSatisfy(\.isHexDigit) })
    }

    /// 앱을 여는 시각 기준으로 시각을 옮겨서, 가장 최근 배포가 늘 1시간 안이에요
    @Test func datesAreShiftedToNow() throws {
        let later = Date.now.addingTimeInterval(60 * 60 * 24 * 30)   // 한 달 뒤에 열어도
        let shifted = SampleData.load(now: later)
        let deployments = try JSONDecoder.daisy.decode(Page<Deployment>.self, from: try #require(shifted["projects/prj_monolith/deployments"])).items
        let newest = try #require(deployments.compactMap(\.createdAt).max())
        #expect(later.timeIntervalSince(newest) < 60 * 60)
        #expect(later.timeIntervalSince(newest) > 0)
    }

    /// 네트워크 없이 APIClient가 그대로 동작하고, 쓰기는 막혀요
    @Test func clientReadsBundleAndBlocksWrites() async throws {
        let client = APIClient(baseURL: SampleData.baseURL, token: SampleData.token, session: SampleData.session)
        let projects = try await client.send(.projects())
        #expect(projects.items.count == 2)

        let waiting = try await client.send(.deployments(projectID: "prj_monolith", state: .awaitingApproval)).items
        #expect(!waiting.isEmpty && waiting.allSatisfy { $0.state == .awaitingApproval })

        // W-12 호출 기록은 배포 하나로 걸러요 (deployment_id 필터)
        let calls = try await client.send(.aiUsage(projectID: "prj_monolith", deploymentID: "dep_m6")).items
        #expect(!calls.isEmpty && calls.allSatisfy { $0.deploymentId == "dep_m6" })

        do {
            _ = try await client.send(.approve(deploymentID: "dep_m6", decision: .approve))
            Issue.record("예시 데이터에서 승인이 통과하면 안 돼요")
        } catch let APIError.server(status, code, _, _) {
            #expect(status == 403)
            #expect(code == "SAMPLE_READ_ONLY")
        }
    }

    /// 예시 데이터 모드는 읽기 전용이고, 로그아웃하면 꺼져요
    @Test @MainActor func appModelSampleMode() {
        let defaults = UserDefaults(suiteName: "SampleDataTests-\(UUID())")!
        let app = AppModel(tokenStore: TokenStore(service: "SampleDataTests-\(UUID())"), defaults: defaults)
        app.signInWithSampleData()
        #expect(app.isSampleMode && app.isSignedIn && app.isViewer)
        #expect(app.client?.baseURL == SampleData.baseURL)
        app.signOut()
        #expect(!app.isSampleMode && !app.isSignedIn)
    }
}
