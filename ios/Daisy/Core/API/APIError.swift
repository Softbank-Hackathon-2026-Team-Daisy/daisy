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
    /// 앱이 만든 문구는 고른 언어로 보여줘요. 서버 오류는 `error.code`마다 문장이 하나라 앱이 코드로 번역하고,
    /// 모르는 코드면 서버 `message`를 그대로 보여줘요 (#74 안 A, 하은현 답 · 서버 `ErrorCode` 9개 + 10/3 `USERNAME_TAKEN`)
    var errorDescription: String? {
        switch self {
        case .notConfigured:
            .app("다시 로그인해 주세요.")
        case .transport:
            // 웹 W-00b와 같은 문구
            .app("서버에 연결하지 못했어요. 잠시 후 다시 시도해 주세요.")
        case .server(401, _, _, _):
            .app("아이디나 비밀번호가 맞지 않아요.")
        case .server(403, _, _, _):
            .app("읽기 전용 계정이라 이 작업을 할 수 없어요.")
        case .server(_, let code, let message, _):
            Self.serverCodeText(code) ?? message
        case .decoding(let detail):
            .app("서버 응답을 해석하지 못했어요. \(detail)")
        case .invalidResponse:
            .app("서버 응답이 올바르지 않아요.")
        }
    }
}

extension APIError {
    /// 서버 `ErrorCode`(server/.../common/error/ErrorCode.java)의 고정 문장을 앱 문구로. 401 · 403은 위에서 따로 다뤄요
    static func serverCodeText(_ code: String) -> String? {
        switch code {
        case "VALIDATION_FAILED": .app("요청 입력을 확인해 주세요.")
        case "NOT_FOUND": .app("요청한 정보를 찾을 수 없어요.")
        case "TARGET_LOCKED": .app("이 환경에서 다른 배포가 진행 중이에요.")
        case "STATE_CONFLICT": .app("지금 상태에서는 할 수 없는 요청이에요.")
        case "MANIFEST_INVALID": .app("배포 명세(deploy.yaml)를 확인해 주세요.")
        case "RATE_LIMITED": .app("요청이 많아요. 잠시 후 다시 시도해 주세요.")
        case "USERNAME_TAKEN": .app("이미 사용 중인 아이디예요.")
        case "INTERNAL": .app("서버에서 오류가 났어요. 잠시 후 다시 시도해 주세요.")
        default: nil
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
