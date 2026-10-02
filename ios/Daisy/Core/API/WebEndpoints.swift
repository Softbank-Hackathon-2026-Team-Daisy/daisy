import Foundation

// 웹 와이어프레임 흐름에 쓰는 요청. 웹과 같은 건 `web/SPEC.md` WR-xx(9/30 서버 답변)를 그대로 쓰고,
// 앱이 더 요청한 것만 (가칭)이에요. SPEC §6-8과 1:1이고, 서버 OpenAPI가 나오면 여기만 고쳐요.

private func jsonBody(_ value: some Encodable) -> Data? {
    try? JSONEncoder.daisy.encode(value)
}

extension Endpoint {
    /// WR-02 · W-02 연결하기. 응답에 deploy.yaml 검증 결과가 같이 와요
    /// 응답은 `{ project, manifest }`예요 (서버 #59, 웹과 같아요). `manifest`는 서버가 아직 검증하지 않아 null일 수 있어요
    static func connectProject(repository: String, branch: String) -> Endpoint<ConnectResult> {
        .init(method: "POST", path: "projects",
              body: jsonBody(ConnectProjectBody(repository: repository, branch: branch)),
              idempotencyKey: UUID().uuidString)
    }

    /// WR-03 · W-02 · W-13 파싱된 deploy.yaml과 오류
    static func manifest(projectID: String) -> Endpoint<Manifest> {
        .init(path: "projects/\(projectID)/manifest")
    }

    /// 프로젝트 상세 (노션 계약 v0.2 3-2) · W-13 저장소 카드
    static func projectDetail(projectID: String) -> Endpoint<ProjectDetail> {
        .init(path: "projects/\(projectID)")
    }

    /// WR-04 · W-04 · W-10 대상 환경 목록 (재사용 판단 · 연결 상태)
    static func deployTargets(projectID: String) -> Endpoint<Page<DeployTarget>> {
        .init(path: "projects/\(projectID)/targets")
    }

    /// WR-05 · W-04 "인프라 코드 생성 · 검증 시작". W-05b "○○만 다시 시도", W-08 "다시 시도"도 같은 커밋으로 새 배포를 만들어요
    /// 빌드는 `source_version_id`로 골라요 (필수, 서버 #36 · #42: 같은 커밋을 다시 빌드해도 고른 빌드로, 커밋으로 추정하지 않아요). `commit`은 확인용으로 같이 보내요
    /// 응답은 생성 결과 `{ id, project_id, state }`만 와요 (10/2 01:07 #42) → 화면은 `id`로 진행 화면을 다시 불러와요
    static func startDeployment(projectID: String, commit: String, sourceVersionID: String, targetIDs: [String]) -> Endpoint<CreatedDeployment> {
        .init(method: "POST", path: "projects/\(projectID)/deployments",
              body: jsonBody(StartDeploymentBody(sourceVersionId: sourceVersionID, commit: commit, targetIds: targetIDs)),
              idempotencyKey: UUID().uuidString)
    }

    /// WR-07 · W-05 생성된 스크립트 (환경별)
    static func deploymentScript(deploymentID: String, targetID: String) -> Endpoint<Script> {
        .init(path: "deployments/\(deploymentID)/targets/\(targetID)/script")
    }

    /// W-05b · W-08 다시 시도: 원본 배포에서 고른 환경만 새 배포로 (10/2 09:57 서버 확정, #42). 응답은 생성과 같은 `{ id, project_id, state }`
    static func retry(_ request: RetryRequest) -> Endpoint<CreatedDeployment> {
        .init(method: "POST", path: "deployments/\(request.deploymentID)/retry",
              body: jsonBody(RetryBody(targetIds: request.targetIDs)), idempotencyKey: UUID().uuidString)
    }

    /// WR-14 · W-09 롤백. 이전 성공 배포의 커밋 + 그때 검증된 스크립트로 새 배포가 생기고, plan 승인을 거쳐요
    static func rollback(deploymentID: String, targetIDs: [String], reason: String) -> Endpoint<CreatedDeployment> {
        .init(method: "POST", path: "deployments/\(deploymentID)/rollback",
              body: jsonBody(RollbackBody(targetIds: targetIDs, reason: reason)), idempotencyKey: UUID().uuidString)
    }

    /// W-12 호출별 AI 사용량 (10/1 서버 결정: 합계는 A-05 plan, 호출별 상세는 이 목록의 `deployment_id` 필터. 응답 모양은 OpenAPI 대기)
    static func aiUsage(projectID: String, deploymentID: String) -> Endpoint<Page<AIUsage.Call>> {
        .init(path: "projects/\(projectID)/ai-usage", query: [("deployment_id", deploymentID)])
    }

    /// A-10 · A-11이 서버에 있는지. 10/2 23:30 개발 서버 OpenAPI(20개)에 없어요 → 화면에서 버튼을 꺼요 (웹 `probeReady`와 같아요)
    static var targetProbesOnServer: Bool { false }

    /// A-10 (가칭) · W-10 "연결 테스트"
    static func testConnection(targetID: String) -> Endpoint<ConnectionTestResult> {
        .init(method: "POST", path: "targets/\(targetID)/test")
    }

    /// A-11 (가칭) · W-10 "리소스 보기"
    static func targetResources(targetID: String) -> Endpoint<Page<EnvironmentResource>> {
        .init(path: "targets/\(targetID)/resources")
    }

    /// WR-10 · W-11 검증된 스크립트 목록
    static func scripts(projectID: String) -> Endpoint<Page<Script>> {
        .init(path: "projects/\(projectID)/scripts")
    }

    /// WR-13 · W-13 "연결 해제". 인프라는 지우지 않아요. 확인 입력은 화면에서 해요
    static func disconnectProject(projectID: String) -> Endpoint<EmptyResponse> {
        .init(method: "DELETE", path: "projects/\(projectID)")
    }

    /// A-07 · W-07 로그, W-08 "원인 보기" (W-05b "오류 로그 보기"는 웹과 같이 스크립트 화면으로 가요)
    static func logs(deploymentID: String, targetID: String? = nil, tail: Int = 200) -> Endpoint<Page<LogLine>> {
        .init(path: "deployments/\(deploymentID)/logs", query: [("target_id", targetID), ("tail", String(tail))])
    }
}

private struct ConnectProjectBody: Encodable, Sendable { let repository: String; let branch: String }
private struct StartDeploymentBody: Encodable, Sendable { let sourceVersionId: String; let commit: String; let targetIds: [String] }
private struct RetryBody: Encodable, Sendable { let targetIds: [String] }
private struct RollbackBody: Encodable, Sendable { let targetIds: [String]; let reason: String }
