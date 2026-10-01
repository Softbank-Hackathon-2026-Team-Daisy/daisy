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
