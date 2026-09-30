import Foundation
import Observation

/// plan 요약(A-05)과 승인 · 거절(W-01).
@MainActor
@Observable
final class PlanApprovalStore {
    let deploymentID: String
    private(set) var plan: LoadState<Plan> = .idle
    private(set) var isSubmitting = false
    private(set) var result: String?
    /// 서버가 받아들인 결정. 화면이 다음 단계로 넘어갈 때 써요.
    private(set) var decided: ApprovalDecision?
    var confirmText = ""

    init(deploymentID: String) {
        self.deploymentID = deploymentID
    }

    func load(using app: AppModel) async {
        guard let client = app.client else { return }
        if plan.value == nil { plan = .loading }
        do {
            plan = .loaded(try await client.send(.plan(deploymentID: deploymentID)))
        } catch {
            app.handle(error)
            if plan.value == nil { plan = .failed(error.localizedDescription) }
        }
    }

    func submit(_ decision: ApprovalDecision, using app: AppModel) async {
        guard let client = app.client, !isSubmitting else { return }
        isSubmitting = true
        defer { isSubmitting = false }
        let needsConfirm = decision == .approve && plan.value?.hasDelete == true
        do {
            _ = try await client.send(.approve(
                deploymentID: deploymentID,
                decision: decision,
                confirmText: needsConfirm ? confirmText : nil
            ))
            result = nil
            decided = decision
        } catch let error as APIError where error.isStateConflict {
            // 웹에서 먼저 처리됐거나 plan이 다시 떠서 상태가 바뀌었어요.
            result = "상태가 바뀌었어요. 최신 plan을 다시 불러왔어요."
            await load(using: app)
        } catch {
            app.handle(error)
            result = error.localizedDescription
        }
    }
}
