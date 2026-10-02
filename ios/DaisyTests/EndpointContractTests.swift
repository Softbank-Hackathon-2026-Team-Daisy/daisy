import Foundation
import Testing
@testable import Daisy

/// 요청 모양이 웹과 같은 계약(`web/SPEC.md` WR-xx, PR #9 은현 님 답변)과 맞는지 확인해요.
/// 서버 OpenAPI가 나오면 이 테스트의 기대값만 고치면 돼요.
struct EndpointContractTests {
    private func json<R>(_ endpoint: Endpoint<R>) throws -> [String: Any] {
        let body = try #require(endpoint.body)
        return try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
    }

    private func query<R>(_ endpoint: Endpoint<R>) -> [String: String] {
        Dictionary(endpoint.query.compactMap { name, value in value.map { (name, $0) } }, uniquingKeysWith: { a, _ in a })
    }

    /// WR-05: 배포 시작은 프로젝트 아래로, 빌드는 `source_version_id`로(필수, #36 · #42), 본문에 project_id 없이, Idempotency-Key 필수
    @Test func startDeployment() throws {
        let endpoint = Endpoint<CreatedDeployment>.startDeployment(projectID: "prj_1", commit: "a1b2c3d", sourceVersionID: "sv_7", targetIDs: ["tgt_aws", "tgt_gcp"])
        #expect(endpoint.method == "POST")
        #expect(endpoint.path == "projects/prj_1/deployments")
        #expect(endpoint.idempotencyKey != nil)
        let body = try json(endpoint)
        #expect(body["source_version_id"] as? String == "sv_7")
        #expect(body["commit"] as? String == "a1b2c3d")
        #expect(body["target_ids"] as? [String] == ["tgt_aws", "tgt_gcp"])
        #expect(body["project_id"] == nil)
    }

    /// 생성 응답은 `{ id, project_id, state }`만 와요 (10/2 01:07 #42). 전체 배포 모양이 아니어도 읽어요
    @Test func createdDeploymentResponse() throws {
        let created = try JSONDecoder.daisy.decode(CreatedDeployment.self, from: Data("""
        { "id": "dep_9", "project_id": "prj_1", "state": "queued" }
        """.utf8))
        #expect(created.id == "dep_9" && created.state == .queued)
    }

    /// WR-14: 롤백 = 환경을 골라 새 배포, reason 포함, Idempotency-Key 필수
    @Test func rollback() throws {
        let endpoint = Endpoint<CreatedDeployment>.rollback(deploymentID: "dep_42", targetIDs: ["tgt_aws"], reason: "헬스체크 실패")
        #expect(endpoint.method == "POST")
        #expect(endpoint.path == "deployments/dep_42/rollback")
        #expect(endpoint.idempotencyKey != nil)
        let body = try json(endpoint)
        #expect(body["target_ids"] as? [String] == ["tgt_aws"])
        #expect(body["reason"] as? String == "헬스체크 실패")
        #expect(body["confirm_text"] == nil)
    }

    /// WR-02: 저장소 연결 본문은 `repository` · `branch`
    @Test func connectProject() throws {
        let endpoint = Endpoint<Project>.connectProject(repository: "https://github.com/o/r", branch: "main")
        #expect(endpoint.method == "POST" && endpoint.path == "projects")
        let body = try json(endpoint)
        #expect(body["repository"] as? String == "https://github.com/o/r")
        #expect(body["branch"] as? String == "main")
    }

    /// WR-06: 승인 화면은 리소스 목록까지 받아요. 요약만 필요한 곳은 쿼리 없이
    @Test func planDetail() {
        #expect(query(Endpoint<Plan>.plan(deploymentID: "dep_42", detail: true)) == ["detail": "resources"])
        #expect(query(Endpoint<Plan>.plan(deploymentID: "dep_42")).isEmpty)
    }

    /// W-01 승인: kind "plan", 삭제 확인 문구, Idempotency-Key
    @Test func approve() throws {
        let endpoint = Endpoint<EmptyResponse>.approve(deploymentID: "dep_42", decision: .approve, confirmText: "aws")
        #expect(endpoint.path == "deployments/dep_42/approvals")
        #expect(endpoint.idempotencyKey != nil)
        let body = try json(endpoint)
        #expect(body["kind"] as? String == "plan")
        #expect(body["decision"] as? String == "approve")
        #expect(body["confirm_text"] as? String == "aws")
        #expect(body["items"] == nil)   // 빈 items는 서버가 400이라, 화면은 비면 보내지 않아요
    }

    /// 10/1 22:39 서버 확정: 사용자가 본 승인 대기 환경 전부를 `items`로
    @Test func approveWithItems() throws {
        let items = [Deployment.ApprovalItem(targetId: "tgt_aws", approvalId: "apv_1"),
                     Deployment.ApprovalItem(targetId: "tgt_gcp", approvalId: "apv_2")]
        let body = try json(Endpoint<EmptyResponse>.approve(deploymentID: "dep_42", decision: .reject, items: items))
        #expect(body["decision"] as? String == "reject")
        let sent = try #require(body["items"] as? [[String: String]])
        #expect(sent == [["target_id": "tgt_aws", "approval_id": "apv_1"], ["target_id": "tgt_gcp", "approval_id": "apv_2"]])
    }

    /// 승인 ID는 A-04 `pending_approvals`에서만 읽어요 (10/2 00:40 서버 답). 단건 `pending_approval`은 쓰지 않아요
    @Test func approvalItemsFromDeployment() throws {
        let deployment = try JSONDecoder.daisy.decode(Deployment.self, from: Data("""
        { "id": "dep_1", "project_id": "prj_1", "commit": "abc", "state": "awaiting_approval",
          "pending_approval": { "approval_id": "apv_old", "kind": "plan" },
          "pending_approvals": [ { "target_id": "tgt_aws", "approval_id": "apv_1" }, { "target_id": "tgt_gcp", "approval_id": "apv_2" } ] }
        """.utf8))
        #expect(deployment.approvalItems(for: ["tgt_aws", "tgt_gcp", "tgt_onprem"]).map(\.approvalId) == ["apv_1", "apv_2"])
        #expect(deployment.approvalItems(for: ["tgt_onprem"]).isEmpty)
    }

    /// A-02 `current_status` (10/2 01:10 #42): `current`가 null이어도 "배포 없음"과 "확인 실패"를 구분해요
    @Test func currentStatus() throws {
        let page = try JSONDecoder.daisy.decode(Page<TargetStatus>.self, from: Data("""
        { "items": [ { "target_id": "tgt_aws", "type": "aws", "name": "aws", "current_status": "unverified", "current": null, "url": null, "health": "unknown" },
                     { "target_id": "tgt_gcp", "type": "gcp", "name": "gcp", "current": null, "url": null, "health": "unknown" } ], "next_cursor": null }
        """.utf8))
        #expect(page.items.map(\.currentStatus) == [.unverified, nil])
    }

    @Test("경로 (WR-03 · WR-04 · WR-07 · WR-10 · WR-13 · A-04)", arguments: [
        (Endpoint<Manifest>.manifest(projectID: "prj_1").path, "projects/prj_1/manifest"),
        (Endpoint<Page<DeployTarget>>.deployTargets(projectID: "prj_1").path, "projects/prj_1/targets"),
        (Endpoint<Script>.deploymentScript(deploymentID: "dep_42", targetID: "tgt_aws").path, "deployments/dep_42/targets/tgt_aws/script"),
        (Endpoint<Page<Script>>.scripts(projectID: "prj_1").path, "projects/prj_1/scripts"),
        (Endpoint<EmptyResponse>.disconnectProject(projectID: "prj_1").path, "projects/prj_1"),
        (Endpoint<Deployment>.deployment(id: "dep_42").path, "deployments/dep_42"),
    ])
    func paths(actual: String, expected: String) {
        #expect(actual == expected)
    }

    /// WR-13: 연결 해제는 본문 없는 DELETE (확인 입력은 화면에서)
    @Test func disconnectHasNoBody() {
        let endpoint = Endpoint<EmptyResponse>.disconnectProject(projectID: "prj_1")
        #expect(endpoint.method == "DELETE")
        #expect(endpoint.body == nil)
    }
}
