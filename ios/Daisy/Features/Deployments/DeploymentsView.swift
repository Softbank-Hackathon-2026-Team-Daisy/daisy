import SwiftUI

/// 배포 메뉴: **진행 중인** 배포의 지금 단계(1 – 6)만 보여줘요 (A-03 목록의 가장 최근 배포가 아직 안 끝났을 때).
/// 보고 있던 배포가 끝나면 이 화면에서 결과(완료 표시)까지 보여주고, 다른 메뉴로 벗어나면 그 결과는 이력(W-09)에서만 봐요.
/// 진행 중인 배포가 없으면 "지금 진행 중인 배포가 없어요"예요 (10/3 박승준 결정).
/// 무엇을 보여줄지는 `DeploymentsFocus`: 승인 화면을 보는 중에 더 새 배포가 생기면 바꾸지 않고 배너로 알려요 (D2).
/// 이 탭 경로에 루트와 같은 배포 화면이 열리면 루트가 이어받아 같은 화면을 두 번 쌓지 않아요 (`RunNavigation`, D12 · P5).
struct DeploymentsView: View {
    @Environment(AppModel.self) private var app
    @Environment(Router.self) private var router
    @Environment(Workspace.self) private var workspace
    @State private var store = DeploymentsStore()
    /// 이 화면에서 보여주고 있는 배포. 끝나도 벗어나기 전까지는 결과를 보여줘요
    @State private var displayed: String?
    /// 이 화면에서 방금 시작한 배포(다시 시도 · 새 배포). 목록이 따라오기 전에도 먼저 보여줘요
    @State private var requested: String?
    /// 방금 시작한 배포의 전환 로딩 (L-02)
    @State private var adopted: RunNavigation.Adoption?
    /// iPhone(아래 탭 바)에는 사이드바 "새 배포"가 없어서 이 화면 위쪽에 둬요
    @Environment(\.tabBarClearance) private var tabBarClearance

    private var focus: DeploymentsFocus {
        DeploymentsFocus(list: store.list.value ?? [], displayed: displayed, requested: requested)
    }

    var body: some View {
        Group {
            if app.selectedProjectID == nil {
                empty { NoProjectView() }
            } else if let shown = focus.shown, store.list.value != nil {
                // iPhone: "새 배포"는 머리줄 제목 "배포"와 같은 줄 오른쪽 위에 둬요 (10/3). 시스템 내비게이션 바는 숨겨요
                RunView(deploymentID: shown, loader: adopted?.deploymentID == shown ? adopted?.loader : nil).id(shown)
                    .environment(\.flowHeaderAccessory, tabBarClearance > 0
                                 ? AnyView(newDeploymentButton.buttonStyle(.glassCircle).help("새 배포")) : nil)
                    // 이 화면에서 다시 시도하면 위에 쌓지 않고 루트가 새 배포로 바뀌어요 (D12)
                    .environment(\.adoptDeployment, DeploymentAdopter(owner: shown) { id in adopt(.init(deploymentID: id, loader: .generate)) })
                    .hidesSystemTitleBar()
                    .safeAreaInset(edge: .top, spacing: 0) {
                        if let newer = focus.newer { newerBanner(newer) }
                    }
            } else {
                // 가장 최근 배포만 봐요. 그보다 예전에 승인 대기로 남겨 둔 배포(새 배포로 넘어가며 버려진 것)는
                // 진행 중이 아니라서 이력에서 처리해요 (10/3 실데이터: 05:13 · 05:20 배포가 승인 대기로 남아 있었어요)
                LoadStateView(state: store.list, retry: { await store.refresh(using: app) }) { all in
                    empty {
                        VStack(spacing: 16) {
                            ContentUnavailableView("지금 진행 중인 배포가 없어요", systemImage: "play",
                                                   description: Text(tabBarClearance > 0 ? "새 배포로 시작해요. 끝난 배포의 결과는 이력에서 봐요."
                                                                     : "사이드바의 새 배포로 시작해요. 끝난 배포의 결과는 이력에서 봐요."))
                            if !all.isEmpty {
                                Button("이력 보기") { router.tab = .history }
                                    .buttonStyle(.glassCapsule)
                            }
                        }
                        .emptyStateCentered()
                    }
                }
            }
        }
        .onChange(of: focus, initial: true) { reconcile() }
        .onChange(of: router.path(for: .deployments).wrappedValue, initial: true) { reconcile() }
        // 다른 메뉴로 벗어나면 지켜본 배포를 잊어요. 끝난 결과는 이제 이력에서만 봐요 (Mac은 화면이 새로 만들어져서 저절로 비워져요)
        .onChange(of: router.tab) { _, tab in
            if tab != .deployments { forget() }
        }
        // 프로젝트를 바꾸면 이전 프로젝트의 배포를 잊어요 (D6)
        .onChange(of: app.selectedProjectID) { forget() }
        // 가장 최근 배포를 다시 찾아요. 웹 · 다른 기기에서 다시 시도하거나 새로 배포하면 새 배포가 생겨서,
        // 열어 둔 화면이 예전 배포에 머물지 않고 새 배포로 넘어가요 (10/3). 배포 한 건의 상태는 RunView가 따로 받아요.
        // 프로젝트 채널의 `deployment.created`가 오면 바로, 아니면 SSE 15초 · 끊기면 5초마다
        .task(id: app.selectedProjectID) {
            await poll(on: workspace.live.changes, every: { PollInterval.seconds(live: workspace.live.isLive) }) {
                await store.refresh(using: app)
            }
        }
    }

    /// 보여줄 배포를 기억하고, 이 탭 경로에 같은 배포 화면이 열렸으면 루트가 이어받아요
    private func reconcile() {
        let focus = focus
        if displayed != focus.shown { displayed = focus.shown }
        if let requested, store.list.value?.contains(where: { $0.id == requested }) == true { self.requested = nil }
        let path = router.path(for: .deployments)
        if let adoption = RunNavigation.adoption(of: path.wrappedValue, rootShows: focus.shown) {
            path.wrappedValue = []
            adopt(adoption)
        }
    }

    /// 루트가 이 배포를 보여줘요 (방금 시작한 배포면 전환 로딩부터)
    private func adopt(_ adoption: RunNavigation.Adoption) {
        router.path(for: .deployments).wrappedValue = []
        if adoption.loader != nil { adopted = adoption }
        if adoption.deploymentID != focus.shown { requested = adoption.deploymentID }
        // 목록 · 사이드바가 새 배포를 바로 알게 해요 (배포 채널이 열려 있는 동안 프로젝트 채널은 닫혀 있어요)
        workspace.refreshSoon()
    }

    private func forget() {
        displayed = nil
        requested = nil
        adopted = nil
    }

    /// D2: 승인 화면을 보는 중에 더 새 배포가 생겼어요. 입력을 날리지 않게 바로 바꾸지 않고 알려요
    private func newerBanner(_ id: String) -> some View {
        Button {
            requested = nil
            displayed = id
        } label: {
            Label("새 배포가 시작됐어요 · 보기", systemImage: "arrow.up.circle")
                .font(.subheadline.weight(.semibold))
        }
        .buttonStyle(.glassCapsule)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private func empty(@ViewBuilder _ content: () -> some View) -> some View {
        PageScaffold(String.app("배포"), subtitle: workspace.project.map { String.app("\($0.name)의 배포") }) {
            newDeploymentButton.buttonStyle(.glassCapsule)
        } content: {
            content()
        }
    }

    private var newDeploymentButton: some View {
        Button { router.push(.newDeployment) } label: {
            Label("새 배포", systemImage: "plus")
        }
        .disabled(app.isViewer || workspace.project == nil)
    }
}
