import Foundation
import Observation

/// plan 요약(A-05) + 리소스 목록(WR-06) + 배포(A-04, 환경별 상태)와 승인 · 거절(W-01).
/// 처음 받은 값에 머물지 않아요 (10/3 검수 A1 · A2): 배포가 바뀌면(`accept`) · 따로 열었으면 직접 다시 받아서(`refresh`)
/// 승인 상태가 바뀐 경우(`ApprovalFingerprint`) plan도 다시 받아요. 입력하던 삭제 확인 문구는 그대로 둬요.
@MainActor
@Observable
final class PlanApprovalStore {
    let deploymentID: String
    private(set) var plan: LoadState<Plan> = .idle
    private(set) var deployment: Deployment?
    /// 배포(A-04)를 한 번도 받지 못했을 때의 오류 (A7). 이때는 "승인할 plan이 없어요" 대신 오류를 보여줘요
    private(set) var deploymentError: String?
    /// 처음 불러온 뒤 다시 받기에 실패한 오류 (D15 · X1)
    private(set) var refreshError: String?
    private(set) var isSubmitting = false
    /// 웹 "처리하지 못했어요" 알림 내용
    private(set) var errorMessage: String?
    /// 서버가 받아들인 결정. 화면이 다음 단계로 넘어갈 때 써요.
    private(set) var decided: ApprovalDecision?
    var confirmText = ""

    init(deploymentID: String, deployment: Deployment? = nil) {
        self.deploymentID = deploymentID
        self.deployment = deployment
    }

    /// 배포 화면(RunView)이 새로 받은 배포를 넘겨줘요. 승인에 관한 값이 바뀌었으면 true → plan을 다시 받아요 (A1)
    @discardableResult
    func accept(_ latest: Deployment) -> Bool {
        let changed = deployment.map(ApprovalFingerprint.init) != ApprovalFingerprint(latest)
        deployment = latest
        deploymentError = nil
        return changed
    }

    /// 배포 + plan 요약 + 상세를 모두 다시 받아요 (처음 열 때 · 실시간 신호 · 409 뒤)
    func load(using app: AppModel) async {
        guard let client = app.client else { return }
        if plan.value == nil { plan = .loading }
        async let latest = fetchDeployment(client)
        await loadPlan(using: app)
        if let result = await latest { apply(result, using: app) }
    }

    /// 따로 연 승인 화면의 폴링: 배포만 받고, 승인 상태가 바뀌었을 때만 plan을 다시 받아요 (A2)
    func refresh(using app: AppModel) async {
        guard let client = app.client else { return }
        guard let result = await fetchDeployment(client) else { return }
        let changed: Bool
        switch result {
        case .success(let latest): changed = accept(latest)
        case .failure: changed = false
        }
        apply(result, using: app)
        if changed || plan.value == nil { await loadPlan(using: app) }
    }

    func reloadPlanIfNeeded(after latest: Deployment, using app: AppModel) async {
        if accept(latest) { await loadPlan(using: app) }
    }

    private func fetchDeployment(_ client: APIClient) async -> Result<Deployment, Error>? {
        do {
            return .success(try await client.send(.deployment(id: deploymentID)))
        } catch {
            return Task.isCancelled ? nil : .failure(error)
        }
    }

    private func apply(_ result: Result<Deployment, Error>, using app: AppModel) {
        switch result {
        case .success(let latest):
            accept(latest)
            refreshError = nil
        case .failure(let error):
            app.handle(error)
            if deployment == nil { deploymentError = error.localizedDescription } else { refreshError = error.localizedDescription }
        }
    }

    private func loadPlan(using app: AppModel) async {
        guard let client = app.client else { return }
        do {
            // 리소스 행은 상세 요청으로 따로 와요 (서버 #51). 상세가 실패해도 요약만으로 승인 화면은 떠요
            async let details = try? client.send(.planDetail(deploymentID: deploymentID))
            let summary = try await client.send(.plan(deploymentID: deploymentID))
            plan = .loaded(summary.merging(await details ?? []))
        } catch {
            if Task.isCancelled { return }
            app.handle(error)
            if plan.value == nil { plan = .failed(error.localizedDescription) } else { refreshError = error.localizedDescription }
        }
    }

    func submit(_ decision: ApprovalDecision, needsConfirm: Bool, targetIDs: [String], using app: AppModel) async {
        guard let client = app.client, !isSubmitting else { return }
        // 서버는 빈 items를 400으로 거절해요 (10/2 00:40). 승인 ID를 못 받았으면 보내지 않고 다시 불러와요
        let items = deployment?.approvalItems(for: targetIDs) ?? []
        guard !items.isEmpty else {
            // 웹 #64와 같은 문구예요
            errorMessage = .app("승인할 수 있는 plan이 없어요. 만료됐을 수 있어서 최신 상태를 다시 불러왔어요.")
            await load(using: app)
            return
        }
        isSubmitting = true
        defer { isSubmitting = false }
        errorMessage = nil
        do {
            _ = try await client.send(.approve(
                deploymentID: deploymentID,
                decision: decision,
                confirmText: needsConfirm ? confirmText : nil,
                items: items
            ))
            decided = decision
        } catch let error as APIError where error.isStateConflict {
            // 웹에서 먼저 처리됐거나 plan이 다시 떠서 상태가 바뀌었어요 (웹 #64와 같은 문구)
            errorMessage = .app("승인 상태가 바뀌어서 최신 상태를 다시 불러왔어요. 다시 확인해 주세요.")
            await load(using: app)
        } catch APIError.server(403, _, _, _) {
            errorMessage = .app("읽기 전용 계정이라 승인할 수 없어요.")
        } catch {
            app.handle(error)
            errorMessage = error.localizedDescription
        }
    }
}
