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
    /// 사용자가 방금 누른 동작이 서버에 반영되기 전까지 보여줄 전환 로딩 (L-01 · L-02 · L-03). 내리는 규칙은 `LoaderRule` (D9)
    private(set) var pendingLoader: TransitionLoader.Stage?
    private var pendingFromState: DeploymentState?
    private var loaderShownAt: Date
    /// 처음 불러온 뒤 다시 받기에 실패한 오류 (D15). 화면은 마지막 값을 보여주고 머리줄에 작게 알려요
    private(set) var refreshError: String?
    /// 끝난 걸 처음 본 때. 서버 `finished_at`이 없으면 이때부터 몇 분 더 받아요 (D14)
    private var finishedSeenAt: Date?
    /// 배포 채널 (`deployments/{id}/events`, E-01). 상태 · 단계 · plan · 승인 이벤트가 오면 바로 다시 불러요
    let live = LiveChannel()

    init(deploymentID: String, loader: TransitionLoader.Stage? = nil, now: Date = .now) {
        self.deploymentID = deploymentID
        self.pendingLoader = loader
        self.loaderShownAt = now
    }

    func refresh(using app: AppModel) async {
        guard let client = app.client else { return }
        if deployment.value == nil { deployment = .loading }
        do {
            accept(try await client.send(.deployment(id: deploymentID)))
        } catch {
            // 화면을 벗어나며 취소된 요청은 오류로 보지 않아요
            if Task.isCancelled { return }
            app.handle(error)
            if deployment.value == nil {
                deployment = .failed(error.localizedDescription)
            } else {
                refreshError = error.localizedDescription
            }
        }
    }

    /// 새로 받은 배포를 반영해요. 테스트도 이 경로로 넣어요
    func accept(_ latest: Deployment, now: Date = .now) {
        deployment = .loaded(latest)
        refreshError = nil
        if latest.state.isFinished, finishedSeenAt == nil { finishedSeenAt = now }
        if let loader = pendingLoader {
            if LoaderRule.shouldDrop(loader, from: pendingFromState, latest: latest, elapsed: now.timeIntervalSince(loaderShownAt)) {
                pendingLoader = nil
            } else if pendingFromState == nil {
                pendingFromState = latest.state
            }
        }
    }

    /// 상한(`LoaderRule.cap`)이 지난 전환 로딩을 내려요. 응답이 오지 않아도 진행 화면을 오래 가리지 않게 (D9)
    func expireLoader(now: Date = .now) {
        if pendingLoader != nil, now.timeIntervalSince(loaderShownAt) >= LoaderRule.cap { pendingLoader = nil }
    }

    var isFinished: Bool { deployment.value?.state.isFinished == true }

    /// 끝난 지 몇 분 지나서 더 받지 않아도 돼요 (D14)
    func isSettled(now: Date = .now) -> Bool {
        RunRefresh.isSettled(deployment.value, finishedSeenAt: finishedSeenAt, now: now)
    }

    /// 배포 채널을 열어 둘지: 진행 중일 때만 (끝났거나 모르는 상태면 닫아요, D1)
    var wantsChannel: Bool { RunRefresh.wantsChannel(deployment.value?.state) }

    /// SSE가 붙어 있으면 15초 안전망, 끊겼는데 진행 중이면 2초, 아니면 5초. 끝난 뒤 · 모르는 상태는 30초 (`RunRefresh`)
    var pollInterval: Double {
        RunRefresh.interval(state: deployment.value?.state, live: live.isLive, loading: pendingLoader != nil)
    }

    func showLoader(_ stage: TransitionLoader.Stage, now: Date = .now) {
        pendingLoader = stage
        pendingFromState = deployment.value?.state
        loaderShownAt = now
    }
}

struct RunView: View {
    @Environment(AppModel.self) private var app
    @Environment(Workspace.self) private var workspace
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
        .environment(\.flowRefreshIssue, store.refreshError.map { message in
            FlowRefreshIssue(message: message) { await store.refresh(using: app) }
        })
        // 끝난 뒤에도 몇 분은 30초마다 받아요: 헬스 · URL이 늦게 채워져요 (D14). 모르는 상태는 30초마다 (D1)
        .task {
            await poll(on: store.live.changes, every: { store.pollInterval }, until: { store.isSettled() }) {
                await store.refresh(using: app)
            }
        }
        // 전환 로딩은 상한이 지나면 내려요 (D9)
        .task(id: store.pendingLoader) {
            guard store.pendingLoader != nil else { return }
            try? await Task.sleep(for: .seconds(LoaderRule.cap))
            store.expireLoader()
        }
        // 끝난 배포는 이벤트가 더 없어서 채널을 닫아요. 열려 있는 동안 프로젝트 채널은 닫아 둬요 (계정당 연결 4개 상한, 앱은 하나만)
        .task(id: store.wantsChannel) {
            guard store.wantsChannel, let stream = app.eventStream else { return }
            store.live.onChange = { [workspace] in workspace.refreshSoon() }
            workspace.hold(store.live)
            defer { workspace.release(store.live) }
            await store.live.listen(stream, path: "deployments/\(store.deploymentID)/events")
        }
    }

    @ViewBuilder
    private func stage(for deployment: Deployment) -> some View {
        switch RunStage(deployment) {
        case .approval:
            // 배포가 바뀔 때마다 넘겨줘요. 승인 화면은 처음 받은 값에 머물지 않고 승인 상태가 바뀌면 plan도 다시 받아요 (A1)
            PlanApprovalView(deploymentID: deployment.id, deployment: deployment) { approved in
                if approved { store.showLoader(.deploy) }
                Task { await store.refresh(using: app) }
            }
        case .generate: GenerateStage(deployment: deployment)
        case .stopped: StoppedStage(deployment: deployment)
        case .apply: ApplyStage(deployment: deployment, live: store.live)
        case .result: ResultStage(deployment: deployment)
        case .unknown: UnknownStage(deployment: deployment)
        }
    }
}

/// 서버가 앱이 모르는 배포 상태를 보냈어요 (D1). 진행 중으로 보지 않고, 환경별 상태만 보여주며 30초마다 다시 확인해요
private struct UnknownStage: View {
    let deployment: Deployment
    @Environment(Router.self) private var router
    @Environment(Workspace.self) private var workspace

    private var targets: [Deployment.Target] { deployment.targets ?? [] }

    var body: some View {
        FlowPage(step: targets.contains(where: \.reachedApply) ? 5 : 4, title: .app("상태를 확인할 수 없어요"),
                 description: .app("앱이 모르는 배포 상태예요. 30초마다 다시 확인해요.")) {
            InlineAlert(.warning, .app("상태를 확인할 수 없어요"),
                        .app("서버가 앱이 모르는 배포 상태를 보냈어요. 잠시 뒤 다시 확인하거나 웹에서 확인해 주세요."))
            if !targets.isEmpty {
                SectionCard(.app("환경별 상태")) {
                    VStack(spacing: 10) {
                        ForEach(targets) { target in
                            ProgressLine(name: workspace.type(of: target.targetId), text: target.step.displayName) {
                                target.resolvedState.badge
                            }
                        }
                    }
                }
            }
            FlowButtons {
                Button("이력 보기") { router.tab = .history }
                    .buttonStyle(.glassCapsule)
            }
        }
    }
}
