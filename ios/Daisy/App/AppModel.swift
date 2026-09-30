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

    private let tokenStore: TokenStore
    private let defaults: UserDefaults

    init(tokenStore: TokenStore = TokenStore(), defaults: UserDefaults = .standard) {
        self.tokenStore = tokenStore
        self.defaults = defaults
        serverURLString = defaults.string(forKey: Keys.serverURL) ?? ""
        selectedProjectID = defaults.string(forKey: Keys.projectID)
        role = defaults.string(forKey: Keys.role)
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
        tokenStore.save(result.accessToken)
        token = result.accessToken
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
        if let error = error as? APIError, error.isUnauthenticated { signOut() }
    }

    private enum Keys {
        static let serverURL = "serverURL"
        static let projectID = "selectedProjectID"
        static let role = "role"
    }
}
