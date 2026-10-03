import Foundation
import Synchronization
import Testing
@testable import Daisy

/// 푸시 (SPEC §6-5 P-01 · P-02, 10/3): 서버 payload → 열 화면, 기기 등록 · 해제 요청 모양, 로그아웃 순서.
/// 운영체제 · 네트워크는 쓰지 않아요 (`PushFake`가 부른 것만 기록해요).
struct PushTests {
    // MARK: payload → 화면

    @Test func approvalOpensPlan() throws {
        let payload = try #require(PushPayload(userInfo: [
            "aps": ["alert": ["loc-key": "push.approval.body", "loc-args": ["sample-monolith"]]],
            "kind": "approval_required", "project_id": "prj_1", "deployment_id": "dep_9",
        ]))
        #expect(payload == PushPayload(kind: .approvalRequired, projectID: "prj_1", deploymentID: "dep_9"))
        #expect(payload.route == .plan("dep_9"))
    }

    @Test(arguments: [
        ("deployment_succeeded", PushPayload.Kind.deploymentSucceeded),
        ("deployment_partially_succeeded", .deploymentPartiallySucceeded),
        ("deployment_failed", .deploymentFailed),
        ("something_new", .unknown),
    ])
    func otherKindsOpenRun(raw: String, kind: PushPayload.Kind) throws {
        let payload = try #require(PushPayload(userInfo: ["kind": raw, "project_id": "prj_1", "deployment_id": "dep_9"]))
        #expect(payload.kind == kind)
        #expect(payload.route == .run("dep_9"))
    }

    /// 빠진 값 · 빈 값은 없는 것으로. 배포 ID가 없으면 화면을 열지 않고, 우리 알림이 아니면 nil
    @Test func missingFieldsAreIgnored() throws {
        let noDeployment = try #require(PushPayload(userInfo: ["kind": "approval_required", "project_id": "prj_1"]))
        #expect(noDeployment.route == nil && noDeployment.projectID == "prj_1")

        let noKind = try #require(PushPayload(userInfo: ["deployment_id": "dep_9", "project_id": ""]))
        #expect(noKind.kind == .unknown && noKind.projectID == nil && noKind.route == .run("dep_9"))

        let wrongTypes = PushPayload(userInfo: ["kind": 3, "project_id": ["x"], "deployment_id": NSNull()])
        #expect(wrongTypes == nil)
        #expect(PushPayload(userInfo: ["aps": ["alert": "hi"]]) == nil)
    }

    /// 누르면 그 프로젝트를 고르고 배포 메뉴에서 화면을 열어요
    @Test @MainActor func tapSelectsProjectAndOpensRoute() {
        let app = PushFake.appModel(token: "tok-real")
        defer { app.signOut() }
        let router = Router()
        PushPayload(kind: .approvalRequired, projectID: "prj_2", deploymentID: "dep_9").open(app: app, router: router)
        #expect(app.selectedProjectID == "prj_2")
        #expect(router.tab == .deployments)
        #expect(router.path(for: .deployments).wrappedValue == [.plan("dep_9")])

        PushPayload(kind: .deploymentFailed, projectID: nil, deploymentID: "dep_10").open(app: app, router: router)
        #expect(app.selectedProjectID == "prj_2")
        #expect(router.path(for: .deployments).wrappedValue == [.run("dep_10")])
    }

    /// 앱이 켜져 있을 때 배너: 설정 › 알림 스위치 (기본 켬). 끝남 스위치는 성공 · 일부 성공 둘 다예요
    @Test func foregroundPresentationFollowsSettings() {
        let suite = "PushTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        func shows(_ kind: PushPayload.Kind) -> Bool {
            PushPayload(kind: kind, projectID: nil, deploymentID: nil).presentsInForeground(defaults: defaults)
        }
        #expect(shows(.approvalRequired) && shows(.deploymentSucceeded) && shows(.deploymentFailed))
        defaults.set(false, forKey: "notify.finished")
        #expect(!shows(.deploymentSucceeded) && !shows(.deploymentPartiallySucceeded))
        #expect(shows(.approvalRequired) && shows(.deploymentFailed) && shows(.unknown))
        defaults.set(false, forKey: "notify.approval")
        defaults.set(false, forKey: "notify.failed")
        #expect(!shows(.approvalRequired) && !shows(.deploymentFailed) && shows(.unknown))
    }

    // MARK: 등록 요청 모양 (P-01)

    @Test func apnsEnvironment() {
        #expect(APNsEnvironment.forBuild(debug: true) == .sandbox)
        #expect(APNsEnvironment.forBuild(debug: false) == .production)
        #if DEBUG
        #expect(APNsEnvironment.current == .sandbox)
        #else
        #expect(APNsEnvironment.current == .production)
        #endif
    }

    @Test func tokenHexEncoding() {
        #expect(PushRegistry.hex(Data([0x00, 0xAB, 0x0F, 0xFF, 0x10])) == "00ab0fff10")
        let token = Data((0..<32).map { UInt8($0 * 8) })
        let hex = PushRegistry.hex(token)
        #expect(hex.count == 64 && hex == hex.lowercased())
        #expect(PushRegistry.hex(Data()) == "")
    }

    @Test func registerRequest() throws {
        let endpoint = Endpoint<EmptyResponse>.registerDevice(
            DeviceRegistration(apnsToken: "00ab", platform: .macos, apnsEnv: .production))
        #expect(endpoint.method == "POST" && endpoint.path == "devices" && endpoint.query.isEmpty)
        #expect(try PushFake.json(endpoint.body) == ["apns_token": "00ab", "platform": "macos", "apns_env": "production"])

        let ios = Endpoint<EmptyResponse>.registerDevice(DeviceRegistration(apnsToken: "ff", platform: .ios, apnsEnv: .sandbox))
        #expect(try PushFake.json(ios.body) == ["apns_token": "ff", "platform": "ios", "apns_env": "sandbox"])
    }

    /// 해제는 토큰을 URL이 아니라 본문으로 (9/29 합의)
    @Test func unregisterRequest() throws {
        let endpoint = Endpoint<EmptyResponse>.unregisterDevice(apnsToken: "00ab")
        #expect(endpoint.method == "DELETE" && endpoint.path == "devices" && endpoint.query.isEmpty)
        #expect(try PushFake.json(endpoint.body) == ["apns_token": "00ab"])

        let request = try APIClient(baseURL: URL(string: "https://api.unibloom.cloud")!, token: "tok")
            .request(for: endpoint)
        #expect(request.url?.absoluteString == "https://api.unibloom.cloud/devices")
        #expect(request.httpMethod == "DELETE")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer tok")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(try PushFake.json(request.httpBody) == ["apns_token": "00ab"])
    }

    // MARK: 등록 · 해제 흐름

    /// 로그인돼 있으면 권한을 묻고 APNs에 등록, 토큰이 오면 그 로그인 토큰으로 POST /devices
    @Test @MainActor func signedInRegisters() async throws {
        let fake = PushFake()
        let app = PushFake.appModel(token: "tok-real", push: fake.registry)
        await fake.registry.activate(for: app)
        #expect(fake.asked == 1 && fake.registered == 1)
        #expect(fake.registry.authorization == .allowed)

        fake.registry.didRegister(deviceToken: Data([0xDE, 0xAD, 0xBE, 0xEF]))
        await fake.registry.lastRequest?.value
        let sent = try #require(fake.sent.all.first)
        #expect(fake.sent.all.count == 1)
        #expect(sent.method == "POST" && sent.path == "devices" && sent.bearer == "tok-real")
        #expect(sent.body == ["apns_token": "deadbeef", "platform": "ios", "apns_env": "sandbox"])
        app.signOut()
    }

    /// 권한을 거절하면 APNs에 등록하지 않아요. 로그인 전에는 묻지도 않아요
    @Test @MainActor func deniedOrSignedOutDoesNotRegister() async {
        let denied = PushFake(granted: false)
        let app = PushFake.appModel(token: "tok-real", push: denied.registry)
        await denied.registry.activate(for: app)
        #expect(denied.asked == 1 && denied.registered == 0)
        #expect(denied.registry.authorization == .denied)
        app.signOut()

        let signedOut = PushFake()
        let nobody = PushFake.appModel(push: signedOut.registry)
        await signedOut.registry.activate(for: nobody)
        signedOut.registry.didRegister(deviceToken: Data([0x01]))
        await signedOut.registry.lastRequest?.value
        #expect(signedOut.asked == 0 && signedOut.registered == 0 && signedOut.sent.all.isEmpty)
    }

    /// 로그아웃은 토큰을 지우기 전에 그 토큰으로 DELETE /devices를 보내요
    @Test @MainActor func signOutUnregistersBeforeClearingToken() async throws {
        let fake = PushFake()
        let app = PushFake.appModel(token: "tok-real", push: fake.registry)
        await fake.registry.activate(for: app)
        fake.registry.didRegister(deviceToken: Data([0x0A, 0x0B]))
        await fake.registry.lastRequest?.value

        app.signOut()
        #expect(app.token == nil && !app.isSignedIn)
        await fake.registry.lastRequest?.value
        let sent = try #require(fake.sent.all.last)
        #expect(fake.sent.all.map(\.method) == ["POST", "DELETE"])
        #expect(sent.path == "devices" && sent.bearer == "tok-real")
        #expect(sent.body == ["apns_token": "0a0b"])
    }

    /// 기기 토큰을 받기 전에 로그아웃하면 보낼 게 없어요
    @Test @MainActor func signOutWithoutDeviceTokenSendsNothing() async {
        let fake = PushFake()
        let app = PushFake.appModel(token: "tok-real", push: fake.registry)
        app.signOut()
        await fake.registry.lastRequest?.value
        #expect(fake.sent.all.isEmpty)
    }
}

// MARK: - 테스트 도구

/// 운영체제 대신 부른 횟수와 서버로 보낸 요청만 기록해요
@MainActor
final class PushFake {
    var asked = 0
    var registered = 0
    let granted: Bool
    let sent = SentDeviceRequests()
    private(set) lazy var registry = PushRegistry(system: PushSystem(
        platform: .ios,
        environment: .sandbox,
        requestAuthorization: { self.asked += 1; return self.granted },
        authorizationStatus: { self.granted ? .allowed : .denied },
        registerForRemoteNotifications: { self.registered += 1 },
        send: { [sent] client, endpoint in sent.record(client, endpoint) }
    ))

    init(granted: Bool = true) {
        self.granted = granted
    }

    /// 로그인 토큰이 있는(또는 없는) AppModel. 키체인 · UserDefaults는 테스트마다 따로 써요
    static func appModel(token: String? = nil, push: PushRegistry? = nil) -> AppModel {
        let store = TokenStore(service: "PushTests-\(UUID().uuidString)")
        if let token { store.save(token) }
        let defaults = UserDefaults(suiteName: "PushTests-\(UUID().uuidString)")!
        return AppModel(tokenStore: store, defaults: defaults, push: push ?? PushFake().registry)
    }

    nonisolated static func json(_ body: Data?) throws -> [String: String] {
        let body = try #require(body)
        return try #require(JSONSerialization.jsonObject(with: body) as? [String: String])
    }
}

final class SentDeviceRequests: Sendable {
    struct Sent: Sendable {
        let bearer: String?
        let method: String
        let path: String
        let body: [String: String]
    }

    private let box = Mutex<[Sent]>([])

    var all: [Sent] { box.withLock { $0 } }

    func record(_ client: APIClient, _ endpoint: Endpoint<EmptyResponse>) {
        let body = endpoint.body.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: String] } ?? [:]
        box.withLock { $0.append(Sent(bearer: client.token, method: endpoint.method, path: endpoint.path, body: body)) }
    }
}
