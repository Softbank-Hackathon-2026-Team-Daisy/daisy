import Foundation
import Observation

/// plan 요약(A-05) + 리소스 목록(WR-06) + 배포(A-04, 환경별 상태)와 승인 · 거절(W-01).
@MainActor
@Observable
final class PlanApprovalStore {
    let deploymentID: String
    private(set) var plan: LoadState<Plan> = .idle
    private(set) var deployment: Deployment?
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

    func load(using app: AppModel) async {
        guard let client = app.client else { return }
        if plan.value == nil { plan = .loading }
        do {
            async let latest = try? client.send(.deployment(id: deploymentID))
            // 리소스 행은 상세 요청으로 따로 와요 (서버 #51). 상세가 실패해도 요약만으로 승인 화면은 떠요
            async let details = try? client.send(.planDetail(deploymentID: deploymentID))
            let summary = try await client.send(.plan(deploymentID: deploymentID))
            plan = .loaded(summary.merging(await details ?? []))
            deployment = await latest ?? deployment
        } catch {
            app.handle(error)
            if plan.value == nil { plan = .failed(error.localizedDescription) }
        }
    }

    func submit(_ decision: ApprovalDecision, needsConfirm: Bool, targetIDs: [String], using app: AppModel) async {
        guard let client = app.client, !isSubmitting else { return }
        // 서버는 빈 items를 400으로 거절해요 (10/2 00:40). 승인 ID를 못 받았으면 보내지 않고 다시 불러와요
        let items = deployment?.approvalItems(for: targetIDs) ?? []
        guard !items.isEmpty else {
            // 웹 #64와 같은 문구예요
            errorMessage = "승인할 수 있는 plan이 없어요. 만료됐을 수 있어서 최신 상태를 다시 불러왔어요."
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
            errorMessage = "승인 상태가 바뀌어서 최신 상태를 다시 불러왔어요. 다시 확인해 주세요."
            await load(using: app)
        } catch APIError.server(403, _, _, _) {
            errorMessage = "읽기 전용 계정이라 승인할 수 없어요."
        } catch {
            app.handle(error)
            errorMessage = error.localizedDescription
        }
    }
}
