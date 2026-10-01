import Foundation
import Testing
@testable import Daisy

/// 웹 `WR-xx` 응답 모양(`web/SPEC.md` §6-4)을 앱 모델이 그대로 받는지 확인해요.
struct ContractDecodingTests {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder.daisy.decode(type, from: Data(json.utf8))
    }

    /// WR-04: reuse · connection (은현 님 답변 모양)
    @Test func deployTarget() throws {
        let target = try decode(DeployTarget.self, #"""
        { "target_id": "tgt_aws", "type": "aws", "name": "aws-prod",
          "reuse": { "available": true, "script_id": "scr_3", "reason": "검증된 스크립트 s3이 있어요" },
          "connection": { "state": "ok", "checked_at": "2026-10-03T10:00:00Z" } }
        """#)
        #expect(target.id == "tgt_aws")
        #expect(target.reuse?.available == true)
        #expect(target.reuse?.reason == "검증된 스크립트 s3이 있어요")
        #expect(target.connection?.state == .ok)
    }

    /// WR-06: replace도 받아요
    @Test func planResourceReplace() throws {
        let resource = try decode(PlanResource.self, #"{ "address": "aws_ecs_service.app", "action": "replace" }"#)
        #expect(resource.action == .replace)
    }

    /// WR-07 · WR-10: files[] · validation · status
    @Test func script() throws {
        let script = try decode(Script.self, #"""
        { "script_id": "scr_1", "target_id": "tgt_aws", "version": "s2", "origin": "ai_generated", "attempt": 2,
          "validation": { "validate": true, "plan": true, "risks": 0 }, "status": "verified", "reuse_count": 1,
          "files": [ { "path": "main.tf", "content": "resource {}" } ] }
        """#)
        #expect(script.id == "scr_1")
        #expect(script.status == .verified && script.origin == .aiGenerated)
        #expect(script.files?.first?.path == "main.tf")
    }

    /// WR-09: A-02에 image_digest
    @Test func targetStatusDigest() throws {
        let status = try decode(TargetStatus.self, #"""
        { "target_id": "tgt_aws", "type": "aws", "name": "AWS", "health": "healthy", "image_digest": "sha256:9f3c" }
        """#)
        #expect(status.imageDigest == "sha256:9f3c")
    }

    /// WR-03: 오류 목록
    @Test func manifestErrors() throws {
        let manifest = try decode(Manifest.self, #"""
        { "port": 8080, "healthcheck": "/health", "env": ["NODE_ENV"], "secrets": [], "database": false,
          "errors": [ { "path": "port", "message": "숫자여야 해요" } ] }
        """#)
        #expect(manifest.port == 8080)
        #expect(manifest.errors?.first?.path == "port")
    }
}
