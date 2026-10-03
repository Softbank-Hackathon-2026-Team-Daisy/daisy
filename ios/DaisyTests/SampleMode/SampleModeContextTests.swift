import Foundation
import Testing
@testable import Daisy

/// 예시 데이터 모드에 들어가고 나올 때 맥락이 섞이지 않아요 (10/3 검수표 SM1 · P6).
/// 예시 데이터 모드를 없앨 때 이 파일도 같이 지워요.
struct SampleModeContextTests {
    /// 실서버 → 로그아웃 → 예시 모드 → 로그아웃: 앞 계정의 데이터 · 경로가 남지 않고, 예시 프로젝트 선택은 저장하지 않아요
    @Test @MainActor func enteringAndLeavingSampleModeResetsContext() async throws {
        let suite = "SampleModeContextTests-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let app = AppModel(tokenStore: TokenStore(service: suite), defaults: defaults, push: PushFake().registry)
        let workspace = Workspace(), router = Router()
        app.bind(workspace: workspace, router: router)

        app.enterSampleMode(role: "owner")
        await workspace.refresh(using: app)
        let sampleProject = try #require(app.selectedProjectID)
        #expect(!workspace.projects.isEmpty)
        #expect(defaults.string(forKey: "selectedProjectID") == nil)  // 예시 프로젝트는 저장하지 않아요
        router.open(.run("dep_sample"))

        app.signOut()
        #expect(workspace.projects.isEmpty && router.path(for: .deployments).wrappedValue.isEmpty)
        #expect(app.selectedProjectID == nil && defaults.string(forKey: "selectedProjectID") == nil)
        #expect(AppModel(tokenStore: TokenStore(service: suite), defaults: defaults).selectedProjectID != sampleProject)
    }

    /// 예시 모드에서 실제 알림을 눌러도 실서버 프로젝트로 바꾸지 않아요 (P6)
    @Test @MainActor func realPushIsIgnoredInSampleMode() {
        let suite = "SampleModeContextTests-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let app = AppModel(tokenStore: TokenStore(service: suite), defaults: defaults, push: PushFake().registry)
        let router = Router()
        app.enterSampleMode(role: "owner")
        PushPayload(kind: .approvalRequired, projectID: "prj_real", deploymentID: "dep_real").open(app: app, router: router)
        #expect(app.selectedProjectID == nil)
        #expect(router.path(for: .deployments).wrappedValue.isEmpty)
        app.signOut()
    }
}
