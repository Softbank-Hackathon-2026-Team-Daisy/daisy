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

    /// WR-05: 배포 시작은 프로젝트 아래로, 본문에 project_id 없이, Idempotency-Key 필수
    @Test func startDeployment() throws {
        let endpoint = Endpoint<Deployment>.startDeployment(projectID: "prj_1", commit: "a1b2c3d", targetIDs: ["tgt_aws", "tgt_gcp"])
        #expect(endpoint.method == "POST")
        #expect(endpoint.path == "projects/prj_1/deployments")
        #expect(endpoint.idempotencyKey != nil)
        let body = try json(endpoint)
        #expect(body["commit"] as? String == "a1b2c3d")
        #expect(body["target_ids"] as? [String] == ["tgt_aws", "tgt_gcp"])
        #expect(body["project_id"] == nil)
        #expect(body["source_version_id"] == nil)   // 빌드 ID를 모르면 키를 빼요
    }

    /// #36: 빌드는 `source_version_id`로 골라요 (같은 커밋을 다시 빌드해도 고른 빌드로)
    @Test func startDeploymentWithBuildID() throws {
        let endpoint = Endpoint<Deployment>.startDeployment(projectID: "prj_1", commit: "a1b2c3d", sourceVersionID: "sv_7", targetIDs: ["tgt_aws"])
        let body = try json(endpoint)
        #expect(body["source_version_id"] as? String == "sv_7")
        #expect(body["commit"] as? String == "a1b2c3d")
        #expect(body["target_ids"] as? [String] == ["tgt_aws"])
    }

    /// WR-14: 롤백 = 환경을 골라 새 배포, reason 포함, Idempotency-Key 필수
    @Test func rollback() throws {
        let endpoint = Endpoint<Deployment>.rollback(deploymentID: "dep_42", targetIDs: ["tgt_aws"], reason: "헬스체크 실패")
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
        #expect(body["items"] == nil)   // 승인 ID를 모르면 빼요
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

    /// 승인 ID 찾는 순서: pending_approvals → 환경별 approval_id → 환경 하나면 pending_approval
    @Test func approvalItemsFromDeployment() throws {
        let deployment = try JSONDecoder.daisy.decode(Deployment.self, from: Data("""
        { "id": "dep_1", "project_id": "prj_1", "commit": "abc", "state": "awaiting_approval",
          "pending_approvals": [ { "target_id": "tgt_aws", "approval_id": "apv_1" } ],
          "targets": [ { "target_id": "tgt_gcp", "step": "plan", "step_state": "done", "attempt": 1, "approval_id": "apv_2" } ] }
        """.utf8))
        #expect(deployment.approvalItems(for: ["tgt_aws", "tgt_gcp", "tgt_onprem"]).map(\.approvalId) == ["apv_1", "apv_2"])
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
