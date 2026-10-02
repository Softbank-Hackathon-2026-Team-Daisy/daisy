import Foundation
import Testing
@testable import Daisy

/// 설정 › 언어 (10/2): 한국어 · English · 日本語. 고른 언어가 저장되고, 문구 · 오류 · 요청 헤더가 그 언어를 따르는지 확인해요.
/// 다른 테스트와 같이 돌아도 섞이지 않게 언어는 `AppLanguage.$override`(TaskLocal)로만 바꿔요.
struct LocalizationTests {
    private let names = ["tgt_onprem": "On-premises", "tgt_aws": "AWS", "tgt_gcp": "GCP"]

    private func freshDefaults() -> (UserDefaults, String) {
        let suite = "LocalizationTests-\(UUID().uuidString)"
        return (UserDefaults(suiteName: suite)!, suite)
    }

    // MARK: 설정 저장

    @Test func settingPersists() {
        let (defaults, suite) = freshDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = LanguageStore(defaults: defaults, device: .korean)
        #expect(store.setting == .system)
        store.setting = .japanese
        #expect(store.resolved == .japanese)

        // 다시 켠 것처럼 새로 만들어도 고른 값이 남아 있어요
        let relaunched = LanguageStore(defaults: defaults, device: .korean)
        #expect(relaunched.setting == .japanese)
        #expect(defaults.string(forKey: LanguageStore.key) == "ja")

        relaunched.setting = .system
        #expect(LanguageStore(defaults: defaults, device: .korean).setting == .system)
    }

    /// 기본값은 "기기 설정 따르기": 기기 언어 중 앱에 있는 첫 언어, 없으면 OS가 고른 언어예요
    @Test func systemSettingFollowsDevice() {
        let (defaults, suite) = freshDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(LanguageStore(defaults: defaults, device: .english).resolved == .english)
        #expect(AppLanguage.device(preferred: ["ja-JP", "en-US"]) == .japanese)
        #expect(AppLanguage.device(preferred: ["en-GB"]) == .english)
        #expect(AppLanguage.device(preferred: ["fr-FR"]) == .korean)
    }

    /// 단위 테스트 호스트는 한국어가 기본이에요 (기존 문구 테스트가 한국어를 확인해요)
    @Test func testHostDefaultsToKorean() {
        #expect(AppLanguage.current == .korean)
        #expect(DeploymentState.running.badge.text == "진행 중")
    }

    // MARK: 번역

    @Test func statusBadgesFollowLanguage() {
        AppLanguage.$override.withValue(.english) {
            #expect(DeploymentState.running.badge.text == "Running")
            #expect(DeploymentState.partiallySucceeded.badge.text == "Partially succeeded")
            #expect(TargetState.awaitingApproval.badge.text == "Awaiting approval")
            #expect(Health.unknown.badge.text == "Not checked")
            #expect(TargetType.onprem.displayName == "On-premises")
        }
        AppLanguage.$override.withValue(.japanese) {
            #expect(DeploymentState.running.badge.text == "進行中")
            #expect(TargetState.awaitingApproval.badge.text == "承認待ち")
            #expect(AppTab.deployments.title == "デプロイ")
        }
    }

    /// 앱이 만든 오류 문구는 번역하고, 서버가 보낸 `message`는 받은 그대로예요
    @Test func apiErrorMessages() {
        // 모르는 코드면 서버 message를 그대로, 아는 코드(서버 ErrorCode 9개)는 앱이 고른 언어로 (#74)
        let serverMessage = APIError.server(status: 409, code: "SOMETHING_NEW", message: "이미 승인됐어요", retryable: true)
        let known = APIError.server(status: 409, code: "TARGET_LOCKED", message: "해당 대상에서 다른 배포가 진행 중입니다.", retryable: false)
        AppLanguage.$override.withValue(.english) {
            #expect(APIError.transport("offline").errorDescription == "Couldn't connect to the server. Please try again in a moment.")
            #expect(APIError.server(status: 401, code: "UNAUTHENTICATED", message: "x", retryable: false).errorDescription
                    == "Incorrect username or password.")
            #expect(serverMessage.errorDescription == "이미 승인됐어요")
            #expect(known.errorDescription == "Another deployment is running on this environment.")
        }
        AppLanguage.$override.withValue(.japanese) {
            #expect(APIError.server(status: 403, code: "FORBIDDEN", message: "x", retryable: false).errorDescription
                    == "読み取り専用アカウントのためこの操作はできません。")
            #expect(serverMessage.errorDescription == "이미 승인됐어요")
        }
    }

    @Test func flowCopyFollowsLanguage() throws {
        let deployment = try Fixture.deployment("running", targets: [
            Fixture.target("tgt_onprem", state: "awaiting_approval", step: "risk_check", stepState: "done"),
            Fixture.target("tgt_aws", state: "failed", step: "plan", stepState: "failed", attempt: 3),
            Fixture.target("tgt_gcp", state: "validating", step: "validate", stepState: "running"),
        ])
        let name = { (id: String) in names[id] ?? id }
        AppLanguage.$override.withValue(.english) {
            let copy = FlowCopy.stopped(deployment, name: name)
            #expect(copy.title == "Only AWS stopped")
            #expect(copy.description == "AWS stopped after failing all 3 attempts. On-premises · GCP will keep going.")
            #expect(copy.toastTitle == "AWS failed validation · other environments continue")
        }
        AppLanguage.$override.withValue(.japanese) {
            #expect(FlowCopy.stopped(deployment, name: name).title == "AWS のみ停止しました")
        }

        let partial = try Fixture.deployment("partially_succeeded", targets: [
            Fixture.target("tgt_aws", state: "succeeded", step: "health_check", stepState: "done"),
            Fixture.target("tgt_gcp", state: "failed", step: "health_check", stepState: "failed"),
        ])
        AppLanguage.$override.withValue(.english) {
            #expect(FlowCopy.result(partial, name: name)
                    == "AWS succeeded; GCP failed the health check. Check that the successful environments run the same image.")
        }
    }

    /// 한 줄 문구 · 시도 · 리소스 · 시각도 고른 언어로 (숫자 · 기호 표기는 웹과 같아요)
    @Test func rowsAndTimesFollowLanguage() throws {
        let target = try JSONDecoder.daisy.decode(Deployment.Target.self, from: Data(
            #"{ "target_id": "tgt_gcp", "state": "validating", "step": "validate", "step_state": "running", "attempt": 1 }"#.utf8))
        let counts = try JSONDecoder.daisy.decode(Plan.Target.Counts.self, from: Data(#"{ "create": 6, "update": 0, "delete": 1 }"#.utf8))
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
        AppLanguage.$override.withValue(.english) {
            #expect(target.generateRow.note == "AI-generated · running validate · Attempt 1/3")
            #expect(counts.summaryText == "Resources +6 ~0 \u{2212}1")
            #expect(TimeText.relative(now.addingTimeInterval(-12 * 60), now: now, calendar: calendar) == "12 min ago")
            #expect(TimeText.relative(now.addingTimeInterval(-60 * 60), now: now, calendar: calendar) == "1 hr ago")
            #expect(TimeText.relative(now.addingTimeInterval(-20), now: now, calendar: calendar) == "Just now")
        }
        AppLanguage.$override.withValue(.japanese) {
            #expect(target.attemptText == "試行 1/3")
            #expect(TimeText.relative(now.addingTimeInterval(-3 * 3600), now: now, calendar: calendar) == "3時間前")
            #expect(AIUsageSummary.Result.passed.text == "呼び出し成功")
        }
    }

    // MARK: 서버 요청

    /// 고른 언어를 `Accept-Language`로 보내서 서버가 나중에 메시지를 그 언어로 줄 수 있어요
    @Test func acceptLanguageHeader() throws {
        let base = URL(string: "https://api.example.com")!
        let japanese = try APIClient(baseURL: base, token: "t", language: .japanese).request(for: .projects())
        #expect(japanese.value(forHTTPHeaderField: "Accept-Language") == "ja")
        #expect(japanese.value(forHTTPHeaderField: "Authorization") == "Bearer t")

        // 기본값은 지금 화면 언어예요
        try AppLanguage.$override.withValue(.english) {
            let request = try APIClient(baseURL: base, token: nil).request(for: .projects())
            #expect(request.value(forHTTPHeaderField: "Accept-Language") == "en")
        }
        let korean = try APIClient(baseURL: base, token: nil).request(for: .projects())
        #expect(korean.value(forHTTPHeaderField: "Accept-Language") == "ko")
    }
}
