import Foundation
import Observation
import os

// APNs 푸시 (SPEC §6-5 P-01 · P-02, 10/3).
// - 실제 로그인 뒤(예시 데이터 모드 제외) 알림 권한을 묻고 APNs에 등록해요. 받은 기기 토큰은 `POST /devices`로 서버에 보내요.
// - 로그아웃할 때는 토큰을 지우기 전에 `DELETE /devices`를 먼저 보내요 (`AppModel.signOut`).
// - 서버가 아직 이 경로를 만들지 않았으면(개발 서버 404) 조용히 넘기고, 다음 실행 · 로그인 때 다시 등록해요.
// - 운영체제 쪽 동작(권한 · 등록 · 플랫폼)은 `PushSystem`으로 받아요. 앱은 `.live`(App/PushAppDelegate.swift), 테스트는 기록만 해요.

/// 기기 등록 요청의 `platform` (P-01)
enum DevicePlatform: String, Encodable, Sendable {
    case ios, macos
}

/// 기기 토큰을 발급한 APNs 서버 (P-01 `apns_env`).
/// Xcode에서 바로 설치한 개발 빌드(Debug)만 `sandbox`이고, TestFlight · Developer ID DMG(Release)는 `production`이에요
enum APNsEnvironment: String, Encodable, Sendable {
    case production, sandbox

    static func forBuild(debug: Bool) -> Self { debug ? .sandbox : .production }

    static var current: Self {
        #if DEBUG
        forBuild(debug: true)
        #else
        forBuild(debug: false)
        #endif
    }
}

/// `POST /devices` 본문: `{ apns_token, platform, apns_env }` (P-01)
struct DeviceRegistration: Encodable, Sendable, Equatable {
    let apnsToken: String
    let platform: DevicePlatform
    let apnsEnv: APNsEnvironment
}

/// 기기(운영체제) 알림 권한. 설정 › 알림에 보여줘요
enum PushAuthorization: Equatable, Sendable {
    /// 아직 확인 전
    case unknown
    /// 아직 묻지 않았어요
    case notDetermined
    case allowed
    case denied
}

/// 운영체제 쪽 동작. 앱에서는 `PushSystem.live`, 테스트에서는 부른 것만 기록하는 값으로 바꿔 끼워요
struct PushSystem {
    var platform: DevicePlatform
    var environment: APNsEnvironment = .current
    /// 알림 · 소리 · 배지 권한을 물어요. 이미 답했으면 창 없이 그 답을 돌려줘요
    var requestAuthorization: @MainActor () async -> Bool
    var authorizationStatus: @MainActor () async -> PushAuthorization
    var registerForRemoteNotifications: @MainActor () -> Void
    /// 서버로 보내기 (본문 없는 204)
    var send: @Sendable (APIClient, Endpoint<EmptyResponse>) async throws -> Void = { client, endpoint in
        _ = try await client.send(endpoint)
    }
}

/// 기기 등록 상태와 알림을 눌러 열 화면. 앱 전체에 하나(`shared`)이고, `AppModel.push`로 닿아요.
@MainActor
@Observable
final class PushRegistry {
    static let shared = PushRegistry(system: .live)

    nonisolated static let log = Logger(subsystem: "com.teamdaisy.daisy", category: "push")

    private(set) var authorization: PushAuthorization = .unknown
    /// 이번 실행에서 APNs가 준 기기 토큰 (소문자 hex)
    private(set) var deviceToken: String?
    /// 알림을 눌러 열 화면. RootView가 지켜보다가 로그인돼 있으면 열고 비워요 (앱이 꺼져 있다가 알림으로 켜질 때도 같아요)
    var pendingOpen: PushPayload?

    @ObservationIgnored private let system: PushSystem
    @ObservationIgnored private weak var app: AppModel?
    /// 마지막으로 보낸 등록 · 해제 요청 (테스트가 끝나기를 기다려요)
    @ObservationIgnored private(set) var lastRequest: Task<Void, Never>?

    init(system: PushSystem) {
        self.system = system
    }

    /// 로그인돼 있을 때(앱을 켤 때 · 로그인할 때마다) 불러요. 권한을 묻고, 허용이면 APNs에 등록해요.
    /// 토큰은 `didRegister(deviceToken:)`로 와요. 예시 데이터 모드에서는 아무것도 하지 않아요
    func activate(for app: AppModel) async {
        self.app = app
        guard app.isSignedIn, !app.isSampleMode else { return }
        let granted = await system.requestAuthorization()
        authorization = await system.authorizationStatus()
        guard granted else { return }
        system.registerForRemoteNotifications()
    }

    /// 설정 화면이 보일 때 · 앱으로 돌아올 때 권한을 다시 읽어요 (기기 설정에서 바꿨을 수 있어요)
    func refreshAuthorization() async {
        authorization = await system.authorizationStatus()
    }

    /// APNs가 준 기기 토큰을 서버에 등록해요 (`POST /devices`)
    func didRegister(deviceToken data: Data) {
        let token = Self.hex(data)
        deviceToken = token
        guard let app, app.isSignedIn, !app.isSampleMode, let client = app.client else { return }
        let device = DeviceRegistration(apnsToken: token, platform: system.platform, apnsEnv: system.environment)
        send(.registerDevice(device), with: client)
    }

    /// 로그아웃 직전(토큰을 지우기 전)에 불러요. 지금 토큰으로 서버에서 이 기기를 빼요 (`DELETE /devices`, 실패해도 그대로 로그아웃)
    func willSignOut(_ app: AppModel) {
        guard !app.isSampleMode, let deviceToken, let client = app.client else { return }
        send(.unregisterDevice(apnsToken: deviceToken), with: client)
    }

    /// 실패는 화면에 보이지 않아요. 서버에 경로가 아직 없으면(404) 다음 실행 · 로그인 때 다시 등록해요
    private func send(_ endpoint: Endpoint<EmptyResponse>, with client: APIClient) {
        let send = system.send
        lastRequest = Task {
            do {
                try await send(client, endpoint)
                Self.log.info("\(endpoint.method, privacy: .public) /devices 성공")
            } catch {
                Self.log.notice("\(endpoint.method, privacy: .public) /devices 실패: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// APNs 기기 토큰 → 소문자 hex (P-01 `apns_token`)
    nonisolated static func hex(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }
}
