import Foundation

/// Daisy 서버 REST 클라이언트. 모든 요청에 Bearer 토큰을 붙여요 (SPEC R-01).
struct APIClient: Sendable {
    let baseURL: URL
    let token: String?
    var session: URLSession = .shared

    func send<Response: Decodable & Sendable>(_ endpoint: Endpoint<Response>) async throws -> Response {
        var request = URLRequest(url: try url(for: endpoint))
        request.httpMethod = endpoint.method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body = endpoint.body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if let key = endpoint.idempotencyKey {
            request.setValue(key, forHTTPHeaderField: "Idempotency-Key")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIError.transport(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }

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
        return encoder
    }()
}
