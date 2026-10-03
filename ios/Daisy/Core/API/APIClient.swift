import Foundation

/// Unibloom 서버 REST 클라이언트. 모든 요청에 Bearer 토큰을 붙여요 (SPEC R-01).
struct APIClient: Sendable {
    let baseURL: URL
    let token: String?
    var session: URLSession = .shared
    /// 설정 › 언어에서 고른 언어. 서버가 메시지를 그 언어로 줄 수 있게 `Accept-Language`로 보내요 (10/2, SPEC R-10)
    var language: AppLanguage = .current
    /// 응답을 못 받은 요청의 Idempotency-Key (웹 #88)
    var idempotencyKeys: IdempotencyKeys = .shared

    /// 요청 하나의 URLRequest: 경로 · 헤더(Bearer, Accept-Language, Idempotency-Key) · 본문
    func request<Response>(for endpoint: Endpoint<Response>) throws -> URLRequest {
        var request = URLRequest(url: try url(for: endpoint))
        request.httpMethod = endpoint.method
        // 상태는 늘 서버에서 새로 받아요. 응답에 캐시 헤더가 없어도 URLSession이 추정 캐시로 옛 값을 줄 수 있어서요 (I3)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(language.rawValue, forHTTPHeaderField: "Accept-Language")
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body = endpoint.body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if let key = endpoint.idempotencyKey {
            request.setValue(idempotencyKeys.key(for: request, fresh: key), forHTTPHeaderField: "Idempotency-Key")
        }
        return request
    }

    func send<Response: Decodable & Sendable>(_ endpoint: Endpoint<Response>) async throws -> Response {
        let request = try request(for: endpoint)
        let key = request.value(forHTTPHeaderField: "Idempotency-Key")
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            if let key { idempotencyKeys.record(request, key: key, outcomeUnknown: true) }
            // 화면이 사라지거나 `.task(id:)`가 다시 시작돼서 취소된 요청은 실패가 아니에요 (X4). 오류 화면을 띄우지 않게 그대로 알려요
            if error.isCancellation || Task.isCancelled { throw CancellationError() }
            throw APIError.transport(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        if let key { idempotencyKeys.record(request, key: key, outcomeUnknown: http.statusCode >= 500) }

        // API가 아니라 웹 페이지(HTML)가 오면 JSON으로 읽지 않고 "응답이 올바르지 않아요"로 보여줘요 (주소 오류 · 터널 오류 페이지)
        if data.first(where: { ![0x20, 0x0A, 0x0D, 0x09].contains($0) }) == UInt8(ascii: "<") {
            throw APIError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            if let envelope = try? JSONDecoder.daisy.decode(ErrorEnvelope.self, from: data) {
                throw APIError.server(
                    status: http.statusCode,
                    code: envelope.error.code,
                    message: envelope.error.message,
                    retryable: envelope.error.retryable ?? false
                )
            }
            throw APIError.server(
                status: http.statusCode,
                code: "HTTP_\(http.statusCode)",
                message: HTTPURLResponse.localizedString(forStatusCode: http.statusCode),
                retryable: false
            )
        }

        // 승인 · 취소는 본문 없이 202 · 204를 줄 수 있어요 (서버 #42 SPEC ③). 빈 본문은 빈 객체로 읽어요 (EmptyResponse만 성공)
        if data.allSatisfy({ $0 == 0x20 || $0 == 0x0A || $0 == 0x0D || $0 == 0x09 }),
           let empty = try? JSONDecoder.daisy.decode(Response.self, from: Data("{}".utf8)) {
            return empty
        }
        do {
            return try JSONDecoder.daisy.decode(Response.self, from: data)
        } catch {
            throw APIError.decoding(String(describing: error))
        }
    }

    private func url<Response>(for endpoint: Endpoint<Response>) throws -> URL {
        var components = URLComponents(
            url: baseURL.appending(path: endpoint.path),
            resolvingAgainstBaseURL: false
        )
        let items = endpoint.query.compactMap { name, value in
            value.map { URLQueryItem(name: name, value: $0) }
        }
        if !items.isEmpty { components?.queryItems = items }
        guard let url = components?.url else { throw APIError.invalidResponse }
        return url
    }
}

extension Error {
    /// 취소된 요청 (`CancellationError` · `URLError.cancelled`). 화면은 이 오류를 실패로 보여주지 않고 그냥 넘겨요 (X4):
    /// `catch { if error.isCancellation { return } … }`
    var isCancellation: Bool {
        if self is CancellationError { return true }
        if let error = self as? URLError, error.code == .cancelled { return true }
        return false
    }
}

extension JSONDecoder {
    /// snake_case 키 (R-06), ISO 8601 UTC 시간 (R-05).
    static let daisy: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { decoder in
            let string = try decoder.singleValueContainer().decode(String.self)
            if let date = try? Date(string, strategy: .iso8601) { return date }
            if let date = try? Date(string, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)) {
                return date
            }
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "ISO 8601 날짜가 아니에요: \(string)"
            ))
        }
        return decoder
    }()
}

extension JSONEncoder {
    static let daisy: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        // 같은 내용이면 같은 본문이 되게 키 순서를 고정해요 (응답 유실 재시도 판단, IdempotencyKeys)
        encoder.outputFormatting = .sortedKeys
        return encoder
    }()
}
