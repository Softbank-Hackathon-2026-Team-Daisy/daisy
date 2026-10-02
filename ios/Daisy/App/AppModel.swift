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

    private let tokenStore: TokenStore
    private let defaults: UserDefaults

    /// Unibloom 서버 주소. 우리가 운영하는 서비스라 쓰는 사람이 주소를 넣지 않아요 — 앱은 늘 이 주소로 가요 (10/2 박승준 결정)
    static let defaultServerURL = "https://api.unibloom.cloud"

    init(tokenStore: TokenStore = TokenStore(), defaults: UserDefaults = .standard) {
        self.tokenStore = tokenStore
        self.defaults = defaults
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

    func enterSampleMode(role: String) { (token, self.role, sessionExpired) = (SampleMode.token(role: role), role, false) }  // SAMPLE-MODE

    func signIn(username: String, password: String) async throws {
        guard let serverURL else { throw APIError.notConfigured }
        let result = try await APIClient(baseURL: serverURL, token: nil)
            .send(.token(username: username, password: password))
        adopt(result, username: username)
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
