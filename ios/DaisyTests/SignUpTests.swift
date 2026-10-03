import Foundation
import Synchronization
import Testing
@testable import Daisy

/// 회원가입 `POST /auth/signup` (10/3 팀 합의): 요청 모양, 성공하면 로그인과 같은 상태, 오류 코드별 문구, 입력 규칙.
/// 가짜 응답을 한 테스트씩 차례로 쓰려고 `.serialized`예요.
@Suite(.serialized)
struct SignUpTests {
    // MARK: 요청 모양

    /// 본문은 snake_case, 아이디는 앞뒤 공백을 빼고 소문자로, 표시 이름도 공백을 빼요
    @Test func requestBody() throws {
        let endpoint = Endpoint<AuthToken>.signup(username: "  Seung_Jun.Park ", password: "pa ss word", displayName: " 박승준 ")
        #expect(endpoint.method == "POST")
        #expect(endpoint.path == "auth/signup")
        #expect(endpoint.idempotencyKey == nil)
        let data = try #require(endpoint.body)
        let body = try #require(JSONSerialization.jsonObject(with: data) as? [String: String])
        #expect(body == ["username": "seung_jun.park", "password": "pa ss word", "display_name": "박승준"])
    }

    /// 표시 이름이 없거나 비면 키를 빼요 (서버가 아이디로 채워요)
    @Test func emptyDisplayNameIsOmitted() throws {
        for name in [nil, "", "   "] as [String?] {
            let endpoint = Endpoint<AuthToken>.signup(username: "abc", password: "12345678", displayName: name)
            let data = try #require(endpoint.body)
            let body = try #require(JSONSerialization.jsonObject(with: data) as? [String: String])
            #expect(body == ["username": "abc", "password": "12345678"])
        }
    }

    /// 로그인 전 요청이라 Bearer 헤더가 없어요
    @Test func requestHasNoAuthorization() throws {
        let client = APIClient(baseURL: URL(string: "https://api.unibloom.cloud")!, token: nil)
        let request = try client.request(for: .signup(username: "abc", password: "12345678"))
        #expect(request.url?.absoluteString == "https://api.unibloom.cloud/auth/signup")
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
    }

    // MARK: 성공

    /// 201이면 로그인과 똑같이 토큰을 키체인에 저장하고 로그인 상태가 돼요 (푸시 등록은 `app.token`을 따라 자동)
    @Test @MainActor func successSignsIn() async throws {
        let (app, store, cleanup) = Self.appModel()
        defer { cleanup() }
        SignupStub.respond(201, #"{ "access_token": "tok_new", "expires_at": "2026-10-04T00:00:00Z", "role": "owner" }"#)

        try await app.signUp(username: " NewUser ", password: "correct horse", displayName: "새 사용자")

        #expect(app.isSignedIn)
        #expect(app.token == "tok_new")
        #expect(store.load() == "tok_new")
        #expect(app.role == "owner" && !app.isViewer)
        #expect(app.username == "newuser")
        #expect(!app.sessionExpired)
        #expect(!app.isSampleMode)  // SAMPLE-MODE

        let sent = try #require(SignupStub.lastRequest)
        #expect(sent.method == "POST")
        #expect(sent.url == "https://api.unibloom.cloud/auth/signup")
        #expect(sent.authorization == nil)
        #expect(sent.body == ["username": "newuser", "password": "correct horse", "display_name": "새 사용자"])
    }

    // MARK: 실패

    @Test(arguments: [
        (409, "USERNAME_TAKEN", SignUpFailure.usernameTaken, "이미 사용 중인 아이디예요. 다른 아이디를 골라 주세요."),
        (429, "RATE_LIMITED", .rateLimited, "가입 요청이 너무 많아요. 몇 분 뒤에 다시 시도해 주세요."),
        (400, "VALIDATION_FAILED", .invalidInput, "아이디 · 비밀번호 · 표시 이름 형식을 확인해 주세요."),
        (403, "FORBIDDEN", .closed, "지금은 회원가입을 받지 않아요. 팀에 계정을 요청해 주세요."),
    ])
    @MainActor func serverErrors(status: Int, code: String, expected: SignUpFailure, message: String) async throws {
        let (app, store, cleanup) = Self.appModel()
        defer { cleanup() }
        SignupStub.respond(status, #"{ "error": { "code": "\#(code)", "message": "server text", "retryable": false } }"#)

        let error = await #expect(throws: APIError.self) {
            try await app.signUp(username: "taken", password: "12345678")
        }
        let failure = SignUpFailure(try #require(error))
        #expect(failure == expected)
        #expect(failure.title == "가입하지 못했어요")
        #expect(failure.message == message)
        #expect(!app.isSignedIn && store.load() == nil)
    }

    /// 서버에 닿지 못하면 로그인 화면과 같은 연결 오류 문구예요
    @Test @MainActor func networkFailure() async throws {
        let (app, store, cleanup) = Self.appModel()
        defer { cleanup() }
        SignupStub.fail(URLError(.notConnectedToInternet))

        let error = await #expect(throws: APIError.self) {
            try await app.signUp(username: "someone", password: "12345678")
        }
        let failure = SignUpFailure(try #require(error))
        #expect(failure == .network)
        #expect(failure.title == "서버에 연결하지 못했어요")
        #expect(failure.message == "서버에 연결하지 못했어요. 잠시 후 다시 시도해 주세요.")
        #expect(!app.isSignedIn && store.load() == nil)
    }

    /// 문구는 고른 언어를 따라요. 새 서버 코드 `USERNAME_TAKEN`은 다른 화면에서도 앱 문구로 보여요
    @Test func messagesFollowLanguage() {
        AppLanguage.$override.withValue(.english) {
            #expect(SignUpFailure.usernameTaken.message == "This username is already taken. Please choose another one.")
            #expect(SignUpFailure.rateLimited.title == "Couldn't create account")
            #expect(APIError.server(status: 409, code: "USERNAME_TAKEN", message: "x", retryable: false).errorDescription
                    == "This username is already taken.")
        }
        AppLanguage.$override.withValue(.japanese) {
            #expect(SignUpFailure.invalidInput.message == "ユーザー名・パスワード・表示名の形式を確認してください。")
        }
    }

    // MARK: 입력 규칙

    @Test(arguments: [
        ("abc", true), ("a.b", true), ("0_x-y.z", true), ("ABC", true), ("  Abc  ", true),
        (String(repeating: "a", count: 32), true),
        ("ab", false), (String(repeating: "a", count: 33), false), (".abc", false), ("_abc", false), ("-abc", false),
        ("ab c", false), ("abc!", false), ("한글아이디", false), ("", false),
    ])
    func usernameRule(username: String, valid: Bool) {
        let form = SignUpForm(username: username)
        #expect(form.usernameValid == valid)
        #expect(form.showsUsernameError == (!valid && !username.isEmpty))
    }

    @Test func passwordAndConfirmationRules() {
        var form = SignUpForm(username: "abc", password: "1234567", confirmation: "1234567")
        #expect(!form.passwordValid && form.showsPasswordError && !form.isValid)

        form.password = "12345678"
        #expect(form.passwordValid && !form.confirmationMatches && form.showsConfirmationError && !form.isValid)
        #expect(form.confirmationHint == "비밀번호가 서로 달라요.")

        form.confirmation = "12345678"
        #expect(form.confirmationMatches && !form.showsConfirmationError && form.isValid)
        #expect(form.confirmationHint == nil)

        // 공백만으로는 안 돼요 · 200자까지
        form.password = String(repeating: " ", count: 8)
        form.confirmation = form.password
        #expect(!form.passwordValid && !form.isValid)
        form.password = String(repeating: "a", count: 201)
        form.confirmation = form.password
        #expect(!form.passwordValid && form.passwordHint == "비밀번호는 200자까지 쓸 수 있어요.")
        form.password = String(repeating: "a", count: 200)
        form.confirmation = form.password
        #expect(form.isValid)
    }

    /// 표시 이름은 선택이고 64자까지 (앞뒤 공백 제외)
    @Test func displayNameRule() {
        var form = SignUpForm(username: "abc", password: "12345678", confirmation: "12345678")
        #expect(form.isValid && !form.showsDisplayNameError)
        form.displayName = " " + String(repeating: "가", count: 64) + " "
        #expect(form.isValid)
        form.displayName = String(repeating: "가", count: 65)
        #expect(!form.isValid && form.showsDisplayNameError && form.displayNameHint == "표시 이름은 64자까지 쓸 수 있어요.")
    }

    /// 아무것도 안 쓴 처음에는 빨간 표시가 없고 버튼은 꺼져 있어요
    @Test func emptyFormShowsNoErrors() {
        let form = SignUpForm()
        #expect(!form.isValid)
        #expect(!form.showsUsernameError && !form.showsPasswordError && !form.showsConfirmationError && !form.showsDisplayNameError)
    }

    // MARK: 도구

    /// 가짜 응답 세션을 쓰는 AppModel. 키체인 · UserDefaults는 테스트마다 따로 쓰고 끝나면 지워요
    @MainActor
    private static func appModel() -> (AppModel, TokenStore, () -> Void) {
        let suite = "SignUpTests-\(UUID().uuidString)"
        let store = TokenStore(service: suite)
        let defaults = UserDefaults(suiteName: suite)!
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [SignupStub.self]
        let app = AppModel(tokenStore: store, defaults: defaults, push: PushFake().registry,
                           authSession: URLSession(configuration: config))
        return (app, store, {
            store.delete()
            defaults.removePersistentDomain(forName: suite)
        })
    }
}

/// 요청을 기록하고 정해 둔 응답(또는 연결 실패)을 돌려줘요
private final class SignupStub: URLProtocol, @unchecked Sendable {
    struct Sent: Sendable {
        let method: String?
        let url: String?
        let authorization: String?
        let body: [String: String]?
    }

    private enum Reply: Sendable {
        case response(Int, String)
        case failure(URLError)
    }

    private static let reply = Mutex<Reply>(.response(500, "{}"))
    private static let sent = Mutex<Sent?>(nil)

    static func respond(_ status: Int, _ body: String) {
        reply.withLock { $0 = .response(status, body) }
        sent.withLock { $0 = nil }
    }

    static func fail(_ error: URLError) {
        reply.withLock { $0 = .failure(error) }
        sent.withLock { $0 = nil }
    }

    static var lastRequest: Sent? { sent.withLock { $0 } }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let data = request.httpBody ?? request.httpBodyStream.map(Self.read)
        let body = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: String] }
        Self.sent.withLock {
            $0 = Sent(method: request.httpMethod, url: request.url?.absoluteString,
                      authorization: request.value(forHTTPHeaderField: "Authorization"), body: body)
        }
        switch Self.reply.withLock({ $0 }) {
        case .failure(let error):
            client?.urlProtocol(self, didFailWithError: error)
        case .response(let status, let text):
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil,
                                           headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(text.utf8))
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {}

    private static func read(_ stream: InputStream) -> Data {
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 { break }
            data.append(buffer, count: count)
        }
        return data
    }
}
