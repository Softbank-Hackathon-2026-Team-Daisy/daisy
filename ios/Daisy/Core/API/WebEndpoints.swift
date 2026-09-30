import Foundation

// 웹 와이어프레임 흐름을 앱에 옮기면서 필요한 요청. 전부 (가칭)이고 SPEC §6-8과 1:1이에요.
// 서버가 경로 · 모양을 정하면 여기만 고쳐요.

struct UploadTicket: Decodable, Sendable {
    let url: URL
    let storageKey: String
    let expiresAt: Date?
}

private func jsonBody(_ value: some Encodable) -> Data? {
    try? JSONEncoder.daisy.encode(value)
}

extension Endpoint {
    /// R-09 · W-00 "데모 계정으로 둘러보기 (읽기 전용)"
    static func demoToken() -> Endpoint<AuthToken> {
        .init(method: "POST", path: "auth/demo")
    }

    /// W-02 저장소 확인: 브랜치 목록과 Dockerfile · deploy.yaml 감지
    static func inspectRepository(url: String, branch: String?) -> Endpoint<RepositoryInspection> {
        .init(path: "repositories/inspect", query: [("url", url), ("branch", branch)])
    }

    /// W-02 연결하기
    static func connectProject(repositoryURL: String, branch: String) -> Endpoint<Project> {
        .init(method: "POST", path: "projects",
                     body: jsonBody(ConnectProjectBody(repositoryUrl: repositoryURL, branch: branch)),
                     idempotencyKey: UUID().uuidString)
    }

    /// W-02b 업로드 주소 받기 (v0.1 3-4)
    static func uploadTicket(projectID: String) -> Endpoint<UploadTicket> {
        .init(method: "POST", path: "projects/\(projectID)/sources/upload-url")
    }

    /// W-02b 업로드한 소스로 연결 (v0.1 3-4)
    static func registerSource(projectID: String, storageKey: String) -> Endpoint<EmptyResponse> {
        .init(method: "POST", path: "projects/\(projectID)/sources", body: jsonBody(RegisterSourceBody(storageKey: storageKey)))
    }

    /// W-02b: 업로드로 시작할 빈 프로젝트
    static func createUploadProject(name: String) -> Endpoint<Project> {
        .init(method: "POST", path: "projects", body: jsonBody(CreateUploadProjectBody(name: name)), idempotencyKey: UUID().uuidString)
    }

    /// W-04 · W-10 대상 환경 목록
    static func deployTargets(projectID: String) -> Endpoint<Page<DeployTarget>> {
        .init(path: "projects/\(projectID)/targets")
    }

    /// W-04 "인프라 코드 생성 · 검증 시작" (v0.1 POST /deployments)
    static func startDeployment(projectID: String, commit: String, targetIDs: [String]) -> Endpoint<Deployment> {
        .init(method: "POST", path: "deployments",
                     body: jsonBody(StartDeploymentBody(projectId: projectID, commit: commit, targetIds: targetIDs)),
                     idempotencyKey: UUID().uuidString)
    }

    /// W-05 생성된 스크립트 (환경별)
    static func deploymentScript(deploymentID: String, targetID: String) -> Endpoint<Script> {
        .init(path: "deployments/\(deploymentID)/targets/\(targetID)/script")
    }

    /// W-05b "처음부터 다시 시도"
    static func retryDeployment(deploymentID: String) -> Endpoint<Deployment> {
        .init(method: "POST", path: "deployments/\(deploymentID)/retry", idempotencyKey: UUID().uuidString)
    }

    /// W-05b "AWS 빼고 계속 (가안)" — Q7 결정 전 가안
    static func excludeTarget(deploymentID: String, targetID: String) -> Endpoint<Deployment> {
        .init(method: "POST", path: "deployments/\(deploymentID)/exclude",
                     body: jsonBody(ExcludeTargetBody(targetId: targetID)), idempotencyKey: UUID().uuidString)
    }

    /// W-08 "다시 시도" (실패한 환경만)
    static func retryTarget(deploymentID: String, targetID: String) -> Endpoint<Deployment> {
        .init(method: "POST", path: "deployments/\(deploymentID)/targets/\(targetID)/retry",
              idempotencyKey: UUID().uuidString)
    }

    /// W-01 · W-08 동일성 검증 (배포 ID가 없으면 지금 떠 있는 것 기준)
    static func parity(projectID: String, deploymentID: String? = nil) -> Endpoint<Parity> {
        .init(path: "projects/\(projectID)/parity", query: [("deployment_id", deploymentID)])
    }

    /// W-09 "롤백" (v0.1 POST /deployments/{id}/rollback)
    static func rollback(deploymentID: String, confirmText: String) -> Endpoint<Deployment> {
        .init(method: "POST", path: "deployments/\(deploymentID)/rollback",
                     body: jsonBody(RollbackBody(confirmText: confirmText)), idempotencyKey: UUID().uuidString)
    }

    /// W-10 "연결 테스트"
    static func testConnection(targetID: String) -> Endpoint<ConnectionTestResult> {
        .init(method: "POST", path: "targets/\(targetID)/test")
    }

    /// W-10 "리소스 보기"
    static func targetResources(targetID: String) -> Endpoint<Page<EnvironmentResource>> {
        .init(path: "targets/\(targetID)/resources")
    }

    /// W-11 검증된 스크립트 목록
    static func scripts(projectID: String) -> Endpoint<Page<Script>> {
        .init(path: "projects/\(projectID)/scripts")
    }

    /// W-12 AI 사용량 (v0.1 GET /costs 대신)
    static func aiUsage(projectID: String) -> Endpoint<AIUsageReport> {
        .init(path: "projects/\(projectID)/ai-usage")
    }

    /// W-13 프로젝트 설정
    static func projectSettings(projectID: String) -> Endpoint<ProjectSettings> {
        .init(path: "projects/\(projectID)/settings")
    }

    /// W-13 "연결 해제" (되돌릴 수 없어요)
    static func disconnectProject(projectID: String, confirmText: String) -> Endpoint<EmptyResponse> {
        .init(method: "DELETE", path: "projects/\(projectID)", body: jsonBody(DisconnectProjectBody(confirmText: confirmText)))
    }

    /// W-05b "오류 로그 보기", W-07 로그, W-08 "원인 보기" (A-07)
    static func logs(deploymentID: String, targetID: String? = nil, tail: Int = 200) -> Endpoint<Page<LogLine>> {
        .init(path: "deployments/\(deploymentID)/logs", query: [("target_id", targetID), ("tail", String(tail))])
    }
}

private struct ConnectProjectBody: Encodable, Sendable { let repositoryUrl: String; let branch: String }
private struct RegisterSourceBody: Encodable, Sendable { let storageKey: String }
private struct CreateUploadProjectBody: Encodable, Sendable { let name: String; let source = "upload" }
private struct StartDeploymentBody: Encodable, Sendable { let projectId: String; let commit: String; let targetIds: [String] }
private struct ExcludeTargetBody: Encodable, Sendable { let targetId: String }
private struct RollbackBody: Encodable, Sendable { let confirmText: String; let reason = "rollback from app" }
private struct DisconnectProjectBody: Encodable, Sendable { let confirmText: String }

extension APIClient {
    /// W-02b: 받은 업로드 주소로 파일을 올려요. 진행률은 0...1.
    func upload(fileAt fileURL: URL, to destination: URL,
                progress: @escaping @Sendable (Double) -> Void) async throws {
        var request = URLRequest(url: destination)
        request.httpMethod = "PUT"
        let delegate = UploadProgress(progress)
        do {
            let (_, response) = try await session.upload(for: request, fromFile: fileURL, delegate: delegate)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw APIError.invalidResponse
            }
        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.transport(error.localizedDescription)
        }
    }
}

private final class UploadProgress: NSObject, URLSessionTaskDelegate, Sendable {
    let report: @Sendable (Double) -> Void
    init(_ report: @escaping @Sendable (Double) -> Void) { self.report = report }

    func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64,
                    totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        guard totalBytesExpectedToSend > 0 else { return }
        report(Double(totalBytesSent) / Double(totalBytesExpectedToSend))
    }
}
