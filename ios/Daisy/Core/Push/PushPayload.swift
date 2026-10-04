import Foundation

/// 서버가 APNs로 보내는 값 (P-02): `aps.alert`(loc-key) + `{ kind, project_id, deployment_id }`.
/// 알림을 누르면 이 값으로 프로젝트를 고르고 화면을 열어요.
struct PushPayload: Equatable, Sendable {
    enum Kind: String, Sendable {
        case approvalRequired = "approval_required"
        case deploymentSucceeded = "deployment_succeeded"
        case deploymentPartiallySucceeded = "deployment_partially_succeeded"
        case deploymentFailed = "deployment_failed"
        /// 서버가 새 값을 보내도 앱이 멈추지 않게
        case unknown
    }

    /// 설정 › 알림 스위치의 `@AppStorage` 키
    enum SettingKey {
        static let approval = "notify.approval"
        /// 성공 · 일부 성공
        static let finished = "notify.finished"
        static let failed = "notify.failed"
    }

    let kind: Kind
    let projectID: String?
    let deploymentID: String?

    init(kind: Kind, projectID: String?, deploymentID: String?) {
        self.kind = kind
        self.projectID = projectID
        self.deploymentID = deploymentID
    }

    /// APNs `userInfo`에서 읽어요. 빠진 값 · 빈 값은 없는 것으로, 모르는 `kind`는 `.unknown`으로 둬요.
    /// 우리 알림이 아니면(세 값이 다 없으면) nil
    init?(userInfo: [AnyHashable: Any]) {
        func text(_ key: String) -> String? {
            guard let value = userInfo[key] as? String, !value.isEmpty else { return nil }
            return value
        }
        let kind = text("kind").map { Kind(rawValue: $0) ?? .unknown }
        let projectID = text("project_id")
        let deploymentID = text("deployment_id")
        guard kind != nil || projectID != nil || deploymentID != nil else { return nil }
        self.init(kind: kind ?? .unknown, projectID: projectID, deploymentID: deploymentID)
    }

    /// 열 화면: 승인 필요 → W-06 변경 사항 확인, 나머지 → 그 배포의 지금 단계. 배포 ID가 없으면 열지 않아요
    var route: Route? {
        guard let deploymentID else { return nil }
        return kind == .approvalRequired ? .plan(deploymentID) : .run(deploymentID)
    }

    /// 앱이 켜져 있을 때 배너를 띄울지. 설정 › 알림 스위치를 따라요 (기본은 켬).
    /// 앱이 꺼져 있거나 뒤에 있을 때 오는 푸시는 운영체제가 바로 보여줘서 앱이 거를 수 없어요 — 서버가 보낼지 정해요
    func presentsInForeground(defaults: UserDefaults) -> Bool {
        let key: String? = switch kind {
        case .approvalRequired: SettingKey.approval
        case .deploymentSucceeded, .deploymentPartiallySucceeded: SettingKey.finished
        case .deploymentFailed: SettingKey.failed
        case .unknown: nil
        }
        guard let key else { return true }
        return defaults.object(forKey: key) as? Bool ?? true
    }

    /// 알림을 눌렀을 때: 그 프로젝트를 고르고 화면을 열어요. 로그인돼 있을 때만 불러요 (RootView, P3).
    /// 다른 프로젝트면 프로젝트를 바꾸면서 모든 메뉴 경로가 비워지고(`Router.apply`), 화면은 배포 메뉴를 비운 뒤 열어요
    /// (`Router.open`, 같은 화면이 이미 맨 위면 그대로). 프로젝트 데이터는 바꾸는 즉시 다시 읽어요 (`Workspace.apply`, P1 · S5)
    @MainActor
    func open(app: AppModel, router: Router) {
        guard app.isSignedIn else { return }
        if app.isSampleMode { return }  // SAMPLE-MODE: 예시 데이터 모드에서 실제 알림은 열지 않아요 (실서버 프로젝트 ID라 화면이 꼬여요, P6)
        if let projectID { app.selectedProjectID = projectID }
        if let route { router.open(route) }
    }
}
