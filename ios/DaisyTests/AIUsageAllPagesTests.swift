import Foundation
import Synchronization
import Testing
@testable import Daisy

/// AI 사용량 전체 합계는 최근 20건이 아니라 프로젝트의 모든 배포를 더해요 (A-03 `next_cursor`를 끝까지, 10/4)
@Suite(.serialized)
struct AIUsageAllPagesTests {
    @Test func followsNextCursorUntilTheEnd() async throws {
        PagingStub.pages = [
            nil: (["dep_3", "dep_2"], "c1"),
            "c1": (["dep_2", "dep_1"], "c2"),  // 겹친 배포는 한 번만
            "c2": (["dep_0"], nil),
        ]
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [PagingStub.self]
        let client = APIClient(baseURL: URL(string: "https://api.example.test")!, token: "t", session: URLSession(configuration: config))

        let all = try await AIUsageStore.allDeployments(client: client, projectID: "prj_1")
        #expect(all.map(\.id) == ["dep_3", "dep_2", "dep_1", "dep_0"])
        #expect(PagingStub.requestedCursors == [nil, "c1", "c2"])
    }
}

private final class PagingStub: URLProtocol, @unchecked Sendable {
    private static let store = Mutex<(pages: [String?: ([String], String?)], cursors: [String?])>(([:], []))
    static var pages: [String?: ([String], String?)] {
        get { store.withLock { $0.pages } }
        set { store.withLock { $0 = (newValue, []) } }
    }
    static var requestedCursors: [String?] { store.withLock { $0.cursors } }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let cursor = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == "cursor" }?.value
        let (ids, next) = Self.store.withLock { state -> ([String], String?) in
            state.cursors.append(cursor)
            return state.pages[cursor] ?? ([], nil)
        }
        let items = ids.map { #"{ "id": "\#($0)", "project_id": "prj_1", "commit": "abc", "state": "succeeded" }"# }
        let nextJSON = next.map { "\"\($0)\"" } ?? "null"
        let body = #"{ "items": [\#(items.joined(separator: ","))], "next_cursor": \#(nextJSON) }"#
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil,
                                       headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
