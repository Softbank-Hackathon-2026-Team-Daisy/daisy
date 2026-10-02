import Foundation
import Testing
@testable import Daisy

/// 샘플 JSON은 테스트 안에만 둬요 (목업 금지 규칙). 모양은 SPEC §6-7.
struct ModelDecodingTests {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder.daisy.decode(type, from: Data(json.utf8))
    }

    @Test func targetStatusPage() throws {
        let page = try decode(Page<TargetStatus>.self, """
        { "items": [ {
            "target_id": "tgt_gcp", "type": "gcp", "name": "gcp-prod",
            "current": { "commit": "2311c0b683ec0f46d0be1c640591245ae8d1c093",
                         "image": "ghcr.io/x/y:2311c0b", "deployment_id": "dep_42",
                         "deployed_at": "2026-10-03T10:12:05Z" },
            "url": "https://hellocalc.example.com", "health": "healthy",
            "checked_at": "2026-10-03T10:13:00.123Z"
          } ], "next_cursor": null }
        """)
        let status = try #require(page.items.first)
        #expect(status.type == .gcp)
        #expect(status.health == .healthy)
        #expect(status.current?.deploymentId == "dep_42")
        #expect(status.checkedAt != nil)
    }

    /// 서버 #38 모양: `current` null · `health: unknown` · `connection_state`, 빌드는 메시지 · 작성자 없이 `queued`, 프로젝트는 `default_branch`
    @Test func serverQueryShapes() throws {
        let status = try #require(try decode(Page<TargetStatus>.self, """
        { "items": [ { "target_id": "tgt_aws", "type": "aws", "name": "aws-prod", "connection_state": "unknown",
                       "checked_at": null, "current": null, "url": null, "health": "unknown",
                       "health_summary": null, "image_digest": null } ], "next_cursor": null }
        """).items.first)
        #expect(status.current == nil)
        #expect(status.health == .unknown)

        let build = try #require(try decode(Page<Build>.self, """
        { "items": [ { "source_version_id": "sv_1", "commit": "2311c0b683ec", "branch": "main",
                       "pipeline": { "status": "queued", "run_url": null }, "image": null, "image_digest": null,
                       "images": null, "deployed_to": [], "received_at": "2026-10-01T12:00:00Z" },
                     { "commit": "abc", "pipeline": { "status": null, "run_url": null } } ],
          "next_cursor": "c2" }
        """).items.first)
        #expect(build.pipeline.status == .queued)
        #expect(build.pipeline.status.badge.text == "대기 중")
        #expect(build.message == nil && build.author == nil)

        let project = try decode(Project.self, """
        { "id": "prj_1", "name": "hellocalc", "repository": "team/hellocalc", "default_branch": "main", "created_at": "2026-10-01T00:00:00Z" }
        """)
        #expect(project.branch == "main")
    }

    @Test func unknownEnumValuesDoNotFail() throws {
        let deployment = try decode(Deployment.self, """
        { "id": "dep_1", "project_id": "prj_1", "commit": "abc", "state": "rolling_back",
          "targets": [ { "target_id": "tgt_aws", "step": "teleport", "step_state": "done",
                         "attempt": 2 } ] }
        """)
        #expect(deployment.state == .unknown)
        #expect(deployment.targets?.first?.step == .unknown)
        #expect(deployment.targets?.first?.attemptText == "시도 2/3")
    }

    @Test func awaitingApprovalState() throws {
        let deployment = try decode(Deployment.self, """
        { "id": "dep_1", "project_id": "prj_1", "commit": "abc", "state": "awaiting_approval",
          "pending_approval": { "approval_id": "apv_7", "kind": "plan" } }
        """)
        #expect(deployment.state == .awaitingApproval)
        #expect(deployment.pendingApproval?.approvalId == "apv_7")
    }

    @Test func planSummaryAndEstimatedCost() throws {
        let plan = try decode(Plan.self, """
        { "deployment_id": "dep_42",
          "targets": [ { "target_id": "tgt_aws", "counts": { "create": 12, "update": 0, "delete": 1 },
                         "has_delete": true,
                         "risks": [ { "level": "high", "rule": "sg-open-world",
                                      "resource": "aws_security_group.web", "message": "열려 있어요" } ] } ],
          "ai_usage": { "tokens": 18234, "cost_krw": 312, "exchange_rate": 1400, "estimated": true } }
        """)
        #expect(plan.hasDelete)
        #expect(plan.targets.first?.risks.first?.level == .high)
        #expect(plan.aiUsage?.costText == "₩312 (추정, 환율 1,400원)")   // 웹 승인 바와 같은 표기
    }

    @Test func errorEnvelope() throws {
        let envelope = try decode(ErrorEnvelope.self, """
        { "error": { "code": "STATE_CONFLICT", "message": "이미 승인됐어요", "retryable": true } }
        """)
        let error = APIError.server(status: 409, code: envelope.error.code, message: envelope.error.message, retryable: true)
        #expect(error.isStateConflict)
    }
}

/// 서버가 본문 없이 202 · 204를 줘도 승인이 "실패"로 보이지 않아요 (서버 #42 SPEC ③)
private final class EmptyBodyProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let response = HTTPURLResponse(url: request.url!, statusCode: 202, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data())
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

struct EmptyBodyTests {
    @Test func approveWithEmpty202() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [EmptyBodyProtocol.self]
        let client = APIClient(baseURL: URL(string: "https://api.example.com")!, token: "t", session: URLSession(configuration: config))
        let items = [Deployment.ApprovalItem(targetId: "tgt_aws", approvalId: "apv_1")]
        _ = try await client.send(.approve(deploymentID: "dep_1", decision: .approve, items: items))
        // 빈 본문은 EmptyResponse만 성공이고, 모양이 있는 응답은 여전히 오류예요
        await #expect(throws: APIError.self) { _ = try await client.send(.deployment(id: "dep_1")) }
    }

    /// A-04 환경에 단계 · 시도가 없어도 배포 화면이 떠요 (서버 안: 확인 전이면 null · 생략)
    @Test func deploymentTargetWithoutStep() throws {
        let deployment = try JSONDecoder.daisy.decode(Deployment.self, from: Data("""
        { "id": "dep_1", "project_id": "prj_1", "commit": "abc", "state": "queued",
          "targets": [ { "target_id": "tgt_aws", "state": "waiting", "step": null, "attempt": null } ] }
        """.utf8))
        let target = try #require(deployment.targets?.first)
        #expect(target.step == .unknown && target.stepState == .unknown && target.attempt == 0)
    }
}

/// 서버 #46 A-04 `GET /deployments/{id}` 확정 모양 (10/2 10:25): 단계 · 시도 · URL · 헬스는 아직 null, 승인 ID는 `pending_approvals`
struct DeploymentDetailContractTests {
    @Test func serverA04Shape() throws {
        let deployment = try JSONDecoder.daisy.decode(Deployment.self, from: Data("""
        { "id": "dep_1", "project_id": "prj_1", "source_version_id": "sv_1", "commit": "2311c0b683ec",
          "image": "docker.io/x/hellocalc:2311c0b683ec", "image_digest": null, "images": null,
          "state": "awaiting_approval", "kind": null, "rolled_back_from": null, "retry_of": null,
          "targets": [ { "target_id": "tgt_aws", "type": "aws", "name": "aws-prod", "state": "awaiting_approval",
                         "step": null, "step_state": null, "attempt": null, "reused_script": false,
                         "url": null, "image_digest": null, "health_summary": null, "error_summary": null,
                         "cancel_requested_at": null, "started_at": "2026-10-02T01:00:00.123456Z", "finished_at": null } ],
          "pending_approvals": [ { "target_id": "tgt_aws", "approval_id": "apv_1" } ],
          "created_by": "acc_demo_owner", "created_at": "2026-10-02T01:00:00Z", "finished_at": null }
        """.utf8))
        #expect(deployment.state == .awaitingApproval && deployment.sourceVersionId == "sv_1")
        #expect(deployment.targets?.first?.attempt == 0 && deployment.targets?.first?.step == .unknown)
        #expect(deployment.approvalItems(for: ["tgt_aws"]).map(\.approvalId) == ["apv_1"])
    }
}
