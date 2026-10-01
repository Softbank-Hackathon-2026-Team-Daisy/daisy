import SwiftUI
import Observation

/// 배포 한 건 (A-04). 서버 상태(9/30 확정 두 층)에 따라 웹 흐름의 해당 화면을 보여줘요.
/// 생성 · 검증 → W-05 · 한 환경 3회 실패 → W-05b · 승인 대기 → W-06 · 배포 중 → W-07 · 끝 → W-08 (규칙은 `RunStage`)
/// W-03 이미지 빌드와 W-04 환경 선택은 배포가 생기기 전 단계라 `Route.build` · `Route.newDeployment`에서 보여줘요.
@MainActor
@Observable
final class RunStore {
    let deploymentID: String
    private(set) var deployment: LoadState<Deployment> = .idle
    /// 사용자가 방금 누른 동작이 서버에 반영되기 전까지 보여줄 전환 로딩 (L-01 · L-02 · L-03)
    var pendingLoader: TransitionLoader.Stage?
    private var pendingFromState: DeploymentState?

    init(deploymentID: String, loader: TransitionLoader.Stage? = nil) {
        self.deploymentID = deploymentID
        self.pendingLoader = loader
    }

    func refresh(using app: AppModel) async {
        guard let client = app.client else { return }
        if deployment.value == nil { deployment = .loading }
        do {
            let latest = try await client.send(.deployment(id: deploymentID))
            deployment = .loaded(latest)
            // 상태가 바뀌면 전환 로딩을 내려요
            if pendingLoader != nil, let from = pendingFromState, latest.state != from { pendingLoader = nil }
            if pendingLoader != nil, pendingFromState == nil { pendingFromState = latest.state }
        } catch {
            app.handle(error)
            if deployment.value == nil { deployment = .failed(error.localizedDescription) }
        }
    }

    func showLoader(_ stage: TransitionLoader.Stage) {
        pendingLoader = stage
        pendingFromState = deployment.value?.state
    }
}

struct RunView: View {
    @Environment(AppModel.self) private var app
    @State private var store: RunStore

    init(deploymentID: String, loader: TransitionLoader.Stage? = nil) {
        _store = State(initialValue: RunStore(deploymentID: deploymentID, loader: loader))
    }

    var body: some View {
        Group {
            if let loader = store.pendingLoader {
                VStack(alignment: .leading, spacing: 0) {
                    FlowStepper(current: loader.step).padding(20)
                    TransitionLoader(stage: loader, environments: store.deployment.value?.targets?.count)
                }
            } else {
                LoadStateView(state: store.deployment, retry: { await store.refresh(using: app) }) { deployment in
                    stage(for: deployment)
                }
            }
        }
        .task { await poll { await store.refresh(using: app) } }
    }

    @ViewBuilder
    private func stage(for deployment: Deployment) -> some View {
        switch RunStage(deployment) {
        case .approval:
            PlanApprovalView(deploymentID: deployment.id, deployment: deployment) { approved in
                if approved { store.showLoader(.deploy) }
                Task { await store.refresh(using: app) }
            }
        case .generate: GenerateStage(deployment: deployment)
        case .stopped: StoppedStage(deployment: deployment)
        case .apply: ApplyStage(deployment: deployment)
        case .result: ResultStage(deployment: deployment)
        }
    }
}
