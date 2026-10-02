import Foundation

/// 요청 하나의 모양. 경로 · 이벤트 이름은 9/29 서버 확정 (SPEC §6-0).
struct Endpoint<Response: Decodable & Sendable>: Sendable {
    var method = "GET"
    let path: String
    var query: [(String, String?)] = []
    var body: Data?
    var idempotencyKey: String?
}

/// 응답 본문을 쓰지 않는 요청용.
struct EmptyResponse: Decodable, Sendable {
    init(from decoder: Decoder) throws {}
}

extension Endpoint {
    /// R-02
    static func token(username: String, password: String) -> Endpoint<AuthToken> {
        .init(
            method: "POST",
            path: "auth/token",
            body: try? JSONEncoder.daisy.encode(["username": username, "password": password])
        )
    }

    /// A-01
    static func projects() -> Endpoint<Page<Project>> {
        .init(path: "projects")
    }

    /// A-02 · D2
    static func targetStatuses(projectID: String) -> Endpoint<Page<TargetStatus>> {
        .init(path: "projects/\(projectID)/targets/status")
    }

    /// A-03 · D3. 승인 대기 목록은 `state: .awaitingApproval`로 걸러요 (A-08 대신).
    static func deployments(
        projectID: String,
        state: DeploymentState? = nil,
        cursor: String? = nil
    ) -> Endpoint<Page<Deployment>> {
        .init(
            path: "projects/\(projectID)/deployments",
            query: [("state", state?.rawValue), ("cursor", cursor)]
        )
    }

    /// A-04 · D2
    static func deployment(id: String) -> Endpoint<Deployment> {
        .init(path: "deployments/\(id)")
    }

    /// A-05 · D3. `detail`이면 환경별 리소스 전체 목록까지 (WR-06, W-06 리소스 행)
    static func plan(deploymentID: String) -> Endpoint<Plan> {
        .init(path: "deployments/\(deploymentID)/plan")
    }

    /// WR-06 · W-06 리소스 행: 요약과 따로, 환경별 배열 `[{ target_id, resources[], plan_text }]`로 와요 (서버 #51)
    static func planDetail(deploymentID: String) -> Endpoint<[PlanDetail]> {
        .init(path: "deployments/\(deploymentID)/plan", query: [("detail", "resources")])
    }

    /// A-06 · D3
    static func builds(projectID: String, cursor: String? = nil) -> Endpoint<Page<Build>> {
        .init(path: "projects/\(projectID)/builds", query: [("cursor", cursor)])
    }

    /// W-01 · D3. 버튼 연타·재시도로 두 번 승인되지 않게 Idempotency-Key를 붙여요.
    static func approve(
        deploymentID: String,
        decision: ApprovalDecision,
        confirmText: String? = nil,
        items: [Deployment.ApprovalItem] = [],
        idempotencyKey: String = UUID().uuidString
    ) -> Endpoint<EmptyResponse> {
        .init(
            method: "POST",
            path: "deployments/\(deploymentID)/approvals",
            body: try? JSONEncoder.daisy.encode(ApprovalRequest(decision: decision, confirmText: confirmText, items: items.isEmpty ? nil : items)),
            idempotencyKey: idempotencyKey
        )
    }
}

/// W-01 요청 본문. 앱은 `kind: "plan"`만 써요.
struct ApprovalRequest: Encodable, Sendable {
    var kind = "plan"
    let decision: ApprovalDecision
    let confirmText: String?
    /// 사용자가 본 승인 대기 환경 전부 `[{ target_id, approval_id }]` (10/1 22:39 서버 확정). 비면 400이라 화면이 보내기 전에 막아요
    let items: [Deployment.ApprovalItem]?
}
