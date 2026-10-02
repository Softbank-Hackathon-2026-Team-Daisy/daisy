import Foundation
import Synchronization

/// 응답을 못 받은 요청을 같은 내용으로 다시 보내면 같은 Idempotency-Key를 다시 써요 (웹 #88 · 이슈 #86과 같아요).
/// 서버가 첫 요청을 처리했는데 응답만 잃은 경우, 새 키로 보내면 배포 · 재시도 · 롤백이 두 번 생길 수 있어요.
/// 성공 · 4xx · 내용이 바뀐 요청은 새 키를 써요.
final class IdempotencyKeys: Sendable {
    static let shared = IdempotencyKeys()

    /// 요청 내용(메서드 · URL · 본문) → 응답을 못 받은 키
    private let pending = Mutex<[String: String]>([:])

    /// 같은 내용이 응답 없이 끝난 적 있으면 그 키, 아니면 `fresh`
    func key(for request: URLRequest, fresh: String) -> String {
        pending.withLock { $0[Self.fingerprint(request)] } ?? fresh
    }

    /// 결과를 기억해요. 응답을 못 받았으면(네트워크 오류 · 5xx) 키를 남기고, 아니면 지워요
    func record(_ request: URLRequest, key: String, outcomeUnknown: Bool) {
        let fingerprint = Self.fingerprint(request)
        pending.withLock { $0[fingerprint] = outcomeUnknown ? key : nil }
    }

    private static func fingerprint(_ request: URLRequest) -> String {
        [request.httpMethod ?? "GET", request.url?.absoluteString ?? "",
         request.httpBody.map { String(decoding: $0, as: UTF8.self) } ?? ""].joined(separator: "\n")
    }
}
