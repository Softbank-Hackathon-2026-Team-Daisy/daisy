import Foundation
import Observation

/// 앱 전체가 공유하는 연결 상태: 서버 주소, 로그인 토큰, 선택한 프로젝트.
@MainActor
@Observable
final class AppModel {
    var serverURLString: String {
        didSet { defaults.set(serverURLString, forKey: Keys.serverURL) }
    }
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

    init(tokenStore: TokenStore = TokenStore(), defaults: UserDefaults = .standard) {
        self.tokenStore = tokenStore
        self.defaults = defaults
        serverURLString = defaults.string(forKey: Keys.serverURL) ?? ""
        selectedProjectID = defaults.string(forKey: Keys.projectID)
        role = defaults.string(forKey: Keys.role)
        username = defaults.string(forKey: Keys.username)
        token = tokenStore.load()
    }

    var serverURL: URL? {
        guard let url = URL(string: serverURLString.trimmingCharacters(in: .whitespaces)),
              url.scheme == "https" || url.scheme == "http",
              url.host() != nil else { return nil }
        return url
    }

    var isSignedIn: Bool { token != nil }
    var isViewer: Bool { role == "viewer" }

    /// 서버 주소와 토큰이 모두 있을 때만 만들어져요.
    var client: APIClient? {
        guard let serverURL, let token else { return nil }
        return APIClient(baseURL: serverURL, token: token)
    }

    func signIn(username: String, password: String) async throws {
        guard let serverURL else { throw APIError.notConfigured }
        let result = try await APIClient(baseURL: serverURL, token: nil)
            .send(.token(username: username, password: password))
        adopt(result, username: username)
    }

    /// W-00 "데모 계정으로 둘러보기 (읽기 전용)" — 서버가 viewer 토큰을 줘요 (R-09 가칭).
    func signInAsDemo() async throws {
        guard let serverURL else { throw APIError.notConfigured }
        let result = try await APIClient(baseURL: serverURL, token: nil).send(.demoToken())
        adopt(result, username: "데모 계정")
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
        static let serverURL = "serverURL"
        static let projectID = "selectedProjectID"
        static let role = "role"
        static let username = "username"
    }
}
