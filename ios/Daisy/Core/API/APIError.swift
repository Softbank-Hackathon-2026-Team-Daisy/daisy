import Foundation

enum APIError: Error, Sendable {
    case notConfigured
    case transport(String)
    case server(status: Int, code: String, message: String, retryable: Bool)
    case decoding(String)
    case invalidResponse

    var isUnauthenticated: Bool {
        if case .server(401, _, _, _) = self { return true }
        return false
    }

    /// 웹에서 먼저 승인했거나 상태가 바뀌었어요. 최신 상태를 다시 불러와요.
    var isStateConflict: Bool {
        if case .server(409, "STATE_CONFLICT", _, _) = self { return true }
        return false
    }

    var isForbidden: Bool {
        if case .server(403, _, _, _) = self { return true }
        return false
    }
}

extension APIError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .notConfigured:
            "설정에서 서버 주소를 넣고 로그인해 주세요."
        case .transport(let message):
            "서버에 연결하지 못했어요. \(message)"
        case .server(403, _, _, _):
            "읽기 전용 계정이라 이 작업을 할 수 없어요."
        case .server(_, _, let message, _):
            message
        case .decoding(let detail):
            "서버 응답을 해석하지 못했어요. \(detail)"
        case .invalidResponse:
            "서버 응답이 올바르지 않아요."
        }
    }
}

/// 서버 에러 봉투 `{ error: { code, message, retryable } }`.
struct ErrorEnvelope: Decodable {
    struct Body: Decodable {
        let code: String
        let message: String
        let retryable: Bool?
    }

    let error: Body
}
