import SwiftUI

// MOCK: 예시 데이터 모드 — UI · UX 확인 전용이에요. 실제 서버에는 절대 연결하지 않아요.
//
// - 들어가는 곳: 로그인 화면 "예시 데이터로 둘러보기 (오프라인)" 하나뿐이에요.
// - 데이터: 이 폴더의 `Fixtures/SampleMode-*.json`. 서버 계약(server/SPEC.md · OpenAPI)과 같은 모양으로 손으로 쓴,
//   실제로 생길 수 있는 모든 경우(상태 · 단계 · null · 빈 목록 · 오류)예요. 스크립트로 만들지 않아요.
// - 통신: 예시 모드의 URLSession은 모든 요청을 이 파일의 `SampleModeProtocol`이 답해요. 네트워크로 나가는 요청이 없어요.
// - 화면마다 "예시 데이터" 배지가 떠요 (루트 AGENTS.md §4-6: 목업은 숨기지 않아요).
//
// 없애는 법 (처음부터 없었던 것처럼):
//   1. 폴더 `ios/Daisy/SampleMode/`와 `ios/DaisyTests/SampleMode/`를 지워요.
//   2. `grep -rn "SAMPLE-MODE" ios`로 나오는 줄을 모두 지워요 (한 줄씩 지워도 코드가 그대로 빌드되게 만들었어요).
//   그 밖에 바꿀 곳은 없어요 — 문구도 이 폴더의 `SampleMode.xcstrings`에만 있어요.

enum SampleMode {
    /// 쓰는 사람이 고르는 역할 (서버 역할과 같아요): 승인 가능한 팀 계정 `owner` · 읽기 전용 계정 `viewer`
    enum Role: String, CaseIterable, Identifiable {
        case owner, viewer
        var id: String { rawValue }
    }

    /// 예시 모드에서만 쓰는 토큰 ("sample-mode.owner"). 키체인에 저장하지 않아요 (앱을 다시 켜면 로그인 화면으로 돌아가요).
    static func token(role: String) -> String { "\(tokenPrefix)\(role)" }
    private static let tokenPrefix = "sample-mode."

    /// 실제로는 없는 주소 (`.invalid`는 예약된 최상위 도메인이에요). 요청은 여기까지도 가지 않고 프로토콜이 답해요.
    static let baseURL = URL(string: "https://sample-mode.invalid")!

    static func isOn(token: String?) -> Bool { token?.hasPrefix(tokenPrefix) == true }

    /// 토큰에 담긴 역할. 실서버처럼 viewer의 쓰기 요청은 403이에요
    static func role(token: String?) -> String? {
        guard let token, isOn(token: token) else { return nil }
        return String(token.dropFirst(tokenPrefix.count))
    }

    /// 예시 모드면 번들 데이터로 답하는 클라이언트, 아니면 nil
    static func client(token: String?) -> APIClient? {
        guard let token, isOn(token: token) else { return nil }
        return APIClient(baseURL: baseURL, token: token, session: session)
    }

    static var displayName: String { text(LocalizedStringResource("예시 데이터", table: "SampleMode")) }

    /// 고른 언어로 찾아요. 글자는 늘 `LocalizedStringResource("…", table: "SampleMode")`로 넘겨서 이 폴더 문구표에만 들어가게 해요
    static func text(_ resource: LocalizedStringResource) -> String {
        var resource = resource
        resource.locale = AppLanguage.current.locale
        return String(localized: resource)
    }

    static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SampleModeProtocol.self]
        return URLSession(configuration: configuration)
    }()
}

extension AppModel {
    var isSampleMode: Bool { SampleMode.isOn(token: token) }
}

// MARK: - 데이터

/// `Fixtures/SampleMode-*.json`을 합친 응답표.
/// 파일 모양: `{ "anchor": "<만든 기준 시각>", "routes": { "GET projects": { "status": 200, "body": … } } }`
/// - 키는 `메서드 경로` 또는 `메서드 경로?이름=값` (쿼리까지 맞는 쪽이 먼저예요)
/// - `status`를 빼면 GET 200 · POST 201 · DELETE 204예요. `body`를 빼면 빈 본문이에요.
/// - 목록 본문 `{ "$items": ["GET deployments/dep_1", …], "next_cursor": null }`은 그 경로들의 본문을 그대로 담아요
///   (목록과 상세가 늘 같게).
/// - 시각은 `anchor` 기준으로 쓰고, 앱이 열 때 지금 시각으로 옮겨서 늘 최근처럼 보여요.
enum SampleFixtures {
    struct Response: Sendable {
        let status: Int
        let body: Data
    }

    static let routes: [String: Response] = load()

    static func load(now: Date = .now, bundle: Bundle = Bundle(for: BundleToken.self)) -> [String: Response] {
        let urls = (bundle.urls(forResourcesWithExtension: "json", subdirectory: nil) ?? [])
            .filter { $0.lastPathComponent.hasPrefix("SampleMode-") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        var table: [String: [String: Any]] = [:]
        for url in urls {
            guard var text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            text = shiftDates(in: text, now: now)
            guard let root = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any],
                  let fileRoutes = root["routes"] as? [String: [String: Any]] else { continue }
            table.merge(fileRoutes) { _, new in new }
        }
        var routes: [String: Response] = [:]
        for (key, value) in table {
            let method = key.split(separator: " ").first.map(String.init) ?? "GET"
            let status = value["status"] as? Int ?? (method == "POST" ? 201 : method == "DELETE" ? 204 : 200)
            var body = value["body"]
            if let list = body as? [String: Any], let refs = list["$items"] as? [String] {
                body = ["items": refs.compactMap { table[$0]?["body"] }, "next_cursor": list["next_cursor"] ?? NSNull()]
            }
            let data = body.flatMap { try? JSONSerialization.data(withJSONObject: $0, options: [.fragmentsAllowed]) } ?? Data()
            routes[key] = Response(status: status, body: data)
        }
        return routes
    }

    /// `anchor`와 지금의 차이만큼 모든 ISO 8601 시각(소수 초 포함)을 옮겨요. 소수 초 자릿수는 그대로 둬요
    static func shiftDates(in text: String, now: Date) -> String {
        guard let anchorText = text.firstMatch(of: #/"anchor": "([0-9T:\-]+Z)"/#)?.1,
              let anchor = try? Date.ISO8601FormatStyle().parse(String(anchorText)) else { return text }
        let delta = now.timeIntervalSince(anchor).rounded()
        return text.replacing(#/(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2})(\.\d+)?Z/#) { match in
            guard let date = try? Date.ISO8601FormatStyle().parse(String(match.output.1) + "Z") else { return String(match.output.0) }
            let shifted = date.addingTimeInterval(delta).formatted(.iso8601).dropLast()
            return shifted + (match.output.2.map(String.init) ?? "") + "Z"
        }
    }

    /// 요청 하나에 대한 응답. 표에 없으면 실서버처럼 404 (`NOT_FOUND`), viewer의 쓰기는 403 (`FORBIDDEN`)이에요
    static func respond(method: String, path: String, query: [URLQueryItem], role: String? = nil) -> Response {
        if method != "GET", role == SampleMode.Role.viewer.rawValue {
            return Response(status: 403, body: error("FORBIDDEN", "권한이 없어요."))
        }
        let specific = query.filter { ["detail", "cursor"].contains($0.name) && $0.value != nil }
            .sorted { $0.name < $1.name }
            .map { "\($0.name)=\($0.value ?? "")" }
            .joined(separator: "&")
        if !specific.isEmpty, let exact = routes["\(method) \(path)?\(specific)"] { return exact }
        guard let response = routes["\(method) \(path)"] else {
            return Response(status: 404, body: error("NOT_FOUND", "요청한 정보를 찾을 수 없어요."))
        }
        // 목록 거르기: 배포 목록 `state`(승인 대기), AI 사용량 `deployment_id`, 로그 `target_id`
        let filters = query.compactMap { item in
            item.value.flatMap { ["state", "deployment_id", "target_id"].contains(item.name) ? (item.name, $0) : nil }
        }
        guard !filters.isEmpty,
              var page = try? JSONSerialization.jsonObject(with: response.body) as? [String: Any],
              let items = page["items"] as? [[String: Any]] else { return response }
        page["items"] = items.filter { row in
            filters.allSatisfy { name, value in (row[name] as? String).map { $0 == value } ?? true }
        }
        return Response(status: response.status, body: (try? JSONSerialization.data(withJSONObject: page)) ?? response.body)
    }

    /// 서버 오류 봉투와 같은 모양 `{ error: { code, message, details, retryable } }`
    private static func error(_ code: String, _ message: String) -> Data {
        (try? JSONSerialization.data(withJSONObject: ["error": ["code": code, "message": message, "details": [String: Any](), "retryable": false]])) ?? Data()
    }

    private final class BundleToken {}
}

/// 예시 모드 세션의 모든 요청을 번들 데이터로 답해요. 주소와 상관없이 네트워크로 내보내지 않아요.
final class SampleModeProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else { return }
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let path = String(url.path.drop { $0 == "/" })
        let token = request.value(forHTTPHeaderField: "Authorization").map { String($0.dropFirst("Bearer ".count)) }
        let response = SampleFixtures.respond(method: request.httpMethod ?? "GET", path: path,
                                              query: components?.queryItems ?? [], role: SampleMode.role(token: token))
        let http = HTTPURLResponse(url: url, statusCode: response.status, httpVersion: "HTTP/1.1",
                                   headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: response.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

// MARK: - 화면

/// "예시 데이터" 배지. 예시 모드일 때만 보여요
struct SampleBadge: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        if app.isSampleMode {
            Label { Text("예시 데이터", tableName: "SampleMode") } icon: { Image(systemName: "shippingbox") }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.orange)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(.orange.opacity(0.15), in: .capsule)
                .accessibilityLabel(Text("예시 데이터로 보는 중이에요", tableName: "SampleMode"))
                .help(SampleMode.text(LocalizedStringResource("서버에 연결하지 않고 앱에 들어 있는 예시 데이터를 보여주고 있어요.", table: "SampleMode")))
        }
    }
}

/// 로그인 화면의 진입점. 누르면 어떤 계정 화면으로 볼지 골라요
struct SampleModeEntryButton: View {
    @Environment(AppModel.self) private var app
    var disabled = false
    @State private var choosing = false

    var body: some View {
        Button { choosing = true } label: {
            Text("예시 데이터로 둘러보기 (오프라인)", tableName: "SampleMode")
        }
        .buttonStyle(.glassCapsule(fullWidth: true, height: 38))
        .disabled(disabled)
        .confirmationDialog(Text("어떤 계정 화면으로 볼까요?", tableName: "SampleMode"), isPresented: $choosing, titleVisibility: .visible) {
            Button { app.enterSampleMode(role: SampleMode.Role.owner.rawValue) } label: {
                Text("승인 가능한 팀 계정으로", tableName: "SampleMode")
            }
            Button { app.enterSampleMode(role: SampleMode.Role.viewer.rawValue) } label: {
                Text("읽기 전용 계정으로", tableName: "SampleMode")
            }
        } message: {
            Text("서버에 연결하지 않고 앱에 들어 있는 예시 데이터를 보여주고 있어요.", tableName: "SampleMode")
        }
    }
}
