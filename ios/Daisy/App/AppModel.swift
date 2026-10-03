import Foundation
import Observation

/// 앱 전체가 공유하는 연결 상태: 서버 주소, 로그인 토큰, 선택한 프로젝트.
@MainActor
@Observable
final class AppModel {
    var selectedProjectID: String? {
        didSet { defaults.set(selectedProjectID, forKey: Keys.projectID) }
    }
    private(set) var token: String?
    private(set) var role: String?
    /// 사이드바 사용자 줄에 보여줄 이름
    private(set) var username: String?
    /// 토큰이 만료돼 로그아웃된 경우. 로그인 화면에 오류 대신 안내를 보여줘요 (웹 W-00 NOTE).
    private(set) var sessionExpired = false

    /// APNs 기기 등록 (SPEC §6-5 P-01). 로그아웃할 때 토큰을 지우기 전에 서버에서 이 기기를 빼요
    let push: PushRegistry

    private let tokenStore: TokenStore
    private let defaults: UserDefaults
    /// 로그인 · 회원가입 요청에 쓰는 세션. 테스트는 가짜 응답을 주는 세션을 넣어요
    private let authSession: URLSession

    /// Unibloom 서버 주소. 우리가 운영하는 서비스라 쓰는 사람이 주소를 넣지 않아요 — 앱은 늘 이 주소로 가요 (10/2 박승준 결정)
    static let defaultServerURL = "https://api.unibloom.cloud"

    init(tokenStore: TokenStore = TokenStore(), defaults: UserDefaults = .standard, push: PushRegistry = .shared,
         authSession: URLSession = .shared) {
        self.tokenStore = tokenStore
        self.authSession = authSession
        self.defaults = defaults
        self.push = push
        selectedProjectID = defaults.string(forKey: Keys.projectID)
        role = defaults.string(forKey: Keys.role)
        username = defaults.string(forKey: Keys.username)
        token = tokenStore.load()
    }

    /// 개발 빌드에서만 실행 환경변수 `UNIBLOOM_SERVER_URL`로 다른 서버를 시험할 수 있어요 (화면에는 칸이 없어요)
    var serverURL: URL? {
        #if DEBUG
        if let override = ProcessInfo.processInfo.environment["UNIBLOOM_SERVER_URL"], let url = URL(string: override) {
            return url
        }
        #endif
        return URL(string: Self.defaultServerURL)
    }

    var isSignedIn: Bool { token != nil }

    /// 사이드바 · 설정에 보일 이름
    var displayName: String? {
        if isSampleMode { return SampleMode.displayName }  // SAMPLE-MODE
        return username
    }
    var isViewer: Bool { role == "viewer" }

    /// 서버 주소와 토큰이 모두 있을 때만 만들어져요.
    var client: APIClient? {
        if let sample = SampleMode.client(token: token) { return sample }  // SAMPLE-MODE
        guard let serverURL, let token else { return nil }
        return APIClient(baseURL: serverURL, token: token)
    }

    /// 실시간(SSE) 연결. `client`와 같은 서버 · 토큰 · 언어예요. 없으면 화면은 폴링만 해요
    var eventStream: EventStream? {
        if isSampleMode { return nil }  // SAMPLE-MODE
        return client.map(EventStream.init(client:))
    }

    func enterSampleMode(role: String) { (token, self.role, sessionExpired) = (SampleMode.token(role: role), role, false) }  // SAMPLE-MODE

    func signIn(username: String, password: String) async throws {
        guard let serverURL else { throw APIError.notConfigured }
        let result = try await APIClient(baseURL: serverURL, token: nil, session: authSession)
            .send(.token(username: username, password: password))
        adopt(result, username: username)
    }

    /// 회원가입 (`POST /auth/signup`). 성공하면 로그인과 똑같이 토큰을 저장해서 바로 로그인 상태가 돼요
    /// (키체인 · 역할 · 푸시 등록은 로그인 경로를 그대로 따라요). 예시 데이터 모드와는 상관없는 실서버 전용 경로예요
    func signUp(username: String, password: String, displayName: String? = nil) async throws {
        guard let serverURL else { throw APIError.notConfigured }
        let result = try await APIClient(baseURL: serverURL, token: nil, session: authSession)
            .send(.signup(username: username, password: password, displayName: displayName))
        adopt(result, username: SignupRequest.normalized(username))
    }

    private func adopt(_ result: AuthToken, username: String) {
        tokenStore.save(result.accessToken)
        self.username = username
        defaults.set(username, forKey: Keys.username)
        token = result.accessToken
        sessionExpired = false
        role = result.role
        defaults.set(result.role, forKey: Keys.role)
    }

    func signOut() {
        push.willSignOut(self)  // 토큰을 지우기 전에 DELETE /devices (P-01)
        tokenStore.delete()
        token = nil
        role = nil
        defaults.removeObject(forKey: Keys.role)
    }

    /// 401이 오면 토큰이 만료된 거라 로그아웃 상태로 돌려요.
    func handle(_ error: Error) {
        if let error = error as? APIError, error.isUnauthenticated {
            signOut()
            sessionExpired = true
        }
    }

    private enum Keys {
        static let projectID = "selectedProjectID"
        static let role = "role"
        static let username = "username"
    }
}
