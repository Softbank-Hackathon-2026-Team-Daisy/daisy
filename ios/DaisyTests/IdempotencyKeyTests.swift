import Foundation
import Synchronization
import Testing
@testable import Daisy

/// 응답을 못 받은 요청을 같은 내용으로 다시 보내면 같은 키, 성공 뒤나 내용이 바뀌면 새 키 (웹 #88 · 이슈 #86)
struct IdempotencyKeyTests {
    @Test func reusesKeyOnlyAfterUnknownOutcome() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ScriptedStatusProtocol.self]
        let client = APIClient(baseURL: URL(string: "https://api.example.com")!, token: "t",
                               session: URLSession(configuration: config), idempotencyKeys: IdempotencyKeys())
        let start = { (targets: [String]) in
            Endpoint<CreatedDeployment>.startDeployment(projectID: "prj_1", commit: "abc", sourceVersionID: "sv_1", targetIDs: targets)
        }
        ScriptedStatusProtocol.statuses.withLock { $0 = [503, 409, 503, 201, 201] }
        ScriptedStatusProtocol.keys.withLock { $0 = [] }

        await #expect(throws: APIError.self) { _ = try await client.send(start(["tgt_aws"])) }  // 503: 응답 모름
        await #expect(throws: APIError.self) { _ = try await client.send(start(["tgt_aws"])) }  // 같은 키 → 409: 결과 받음
        await #expect(throws: APIError.self) { _ = try await client.send(start(["tgt_aws"])) }  // 새 키 → 503
        _ = try await client.send(start(["tgt_aws", "tgt_gcp"]))                                // 내용이 바뀌면 새 키
        _ = try await client.send(start(["tgt_aws"]))                                           // 앞의 503 키를 다시 써요

        let keys = ScriptedStatusProtocol.keys.withLock { $0 }
        #expect(keys.count == 5)
        #expect(keys[0] == keys[1])
        #expect(keys[2] != keys[1])
        #expect(keys[3] != keys[2])
        #expect(keys[4] == keys[2])
    }
}

private final class ScriptedStatusProtocol: URLProtocol, @unchecked Sendable {
    static let statuses = Mutex<[Int]>([])
    static let keys = Mutex<[String]>([])

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.keys.withLock { $0.append(request.value(forHTTPHeaderField: "Idempotency-Key") ?? "") }
        let status = Self.statuses.withLock { $0.isEmpty ? 500 : $0.removeFirst() }
        let body = status == 201
            ? #"{ "id": "dep_1", "project_id": "prj_1", "state": "queued" }"#
            : #"{ "error": { "code": "X", "message": "x" } }"#
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
