import Foundation

// MOCK: 예시 데이터 모드 (9/30 담당자 결정). 서버 없이 앱을 둘러보는 오프라인 번들이에요.
// - 데이터: Resources/SampleData/sample.json (scripts/sample-data/generate.py가 실제 GitHub 커밋 · deploy.yaml로 만들어요)
// - 모든 화면에 "예시 데이터" 배지가 떠요 (루트 AGENTS.md §4-6: 목업은 숨기지 않아요)
// - 실서버 연결이 기본이고, 두 데이터를 섞지 않아요. 쓰기 요청은 모두 막아요.
enum SampleData {
    /// 실제로는 접속하지 않는 주소 (`.invalid`는 예약된 최상위 도메인이에요)
    static let baseURL = URL(string: "https://sample.daisy.invalid")!
    static let token = "sample-data"

    /// 경로 → 응답 JSON. 만든 시각과 지금의 차이만큼 모든 시각을 옮겨서 늘 최근처럼 보여요.
    static let responses: [String: Data] = load()

    static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SampleDataProtocol.self]
        return URLSession(configuration: configuration)
    }()

    static func load(now: Date = .now) -> [String: Data] {
        guard let url = Bundle(for: BundleToken.self).url(forResource: "sample", withExtension: "json"),
              var text = try? String(contentsOf: url, encoding: .utf8) else { return [:] }
        let isoFormat = Date.ISO8601FormatStyle()
        if let generatedLine = text.firstMatch(of: #/"generated_at": "([0-9T:\-]+Z)"/#),
           let generatedAt = try? isoFormat.parse(String(generatedLine.1)) {
            let delta = now.timeIntervalSince(generatedAt)
            text = text.replacing(#/\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z/#) { match in
                guard let date = try? isoFormat.parse(String(match.output)) else { return String(match.output) }
                return date.addingTimeInterval(delta).formatted(isoFormat)
            }
        }
        guard let root = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any],
              let responses = root["responses"] as? [String: Any] else { return [:] }
        return responses.compactMapValues { try? JSONSerialization.data(withJSONObject: $0) }
    }

    /// 요청 하나에 대한 (상태 코드, 본문)
    static func respond(method: String, path: String, query: [URLQueryItem]) -> (Int, Data) {
        guard method == "GET" else {
            return (403, error("SAMPLE_READ_ONLY", .app("예시 데이터라 바꿀 수 없어요. 서버에 연결해서 해 보세요.")))
        }
        guard var body = responses[path] else {
            return (404, error("NOT_FOUND", .app("예시 데이터에 없는 화면이에요.")))
        }
        // 목록 필터: 배포 목록의 `state`(승인 대기 배지), AI 사용량의 `deployment_id`
        let filters = query.compactMap { item in
            item.value.flatMap { ["state", "deployment_id"].contains(item.name) ? (item.name, $0) : nil }
        }
        if !filters.isEmpty,
           var page = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
           let items = page["items"] as? [[String: Any]] {
            page["items"] = items.filter { row in filters.allSatisfy { row[$0.0] as? String == $0.1 } }
            body = (try? JSONSerialization.data(withJSONObject: page)) ?? body
        }
        return (200, body)
    }

    private static func error(_ code: String, _ message: String) -> Data {
        (try? JSONSerialization.data(withJSONObject: ["error": ["code": code, "message": message, "retryable": false]])) ?? Data()
    }

    private final class BundleToken {}
}

/// 예시 데이터 주소로 가는 요청을 번들 파일로 답해요. 네트워크를 쓰지 않아요.
final class SampleDataProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == SampleData.baseURL.host
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else { return }
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let path = String(url.path.drop { $0 == "/" })
        let (status, body) = SampleData.respond(method: request.httpMethod ?? "GET", path: path,
                                                query: components?.queryItems ?? [])
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
