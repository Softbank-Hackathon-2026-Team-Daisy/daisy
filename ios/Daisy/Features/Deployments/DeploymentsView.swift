import SwiftUI

/// 배포 메뉴: 웹 사이드바 "배포"와 같이 가장 최근 배포의 지금 단계(W-05 ~ W-08)를 바로 보여줘요 (A-03 목록의 첫 건).
/// 지난 배포는 이력(W-09)에서 봐요. 배포가 없으면 "새 배포"로 시작해요.
struct DeploymentsView: View {
    @Environment(AppModel.self) private var app
    @Environment(Router.self) private var router
    @Environment(Workspace.self) private var workspace
    @State private var store = DeploymentsStore()
    /// iPhone(아래 탭 바)에는 사이드바 "새 배포"가 없어서 이 화면 위쪽에 둬요
    @Environment(\.tabBarClearance) private var tabBarClearance

    var body: some View {
        Group {
            if app.selectedProjectID == nil {
                empty { NoProjectView() }
            } else {
                LoadStateView(state: store.list, retry: { await store.refresh(using: app) }) { all in
                    if let latest = all.first {
                        // iPhone: "새 배포"는 머리줄 제목 "배포"와 같은 줄 오른쪽 위에 둬요 (10/3). 시스템 내비게이션 바는 숨겨요
                        RunView(deploymentID: latest.id).id(latest.id)
                            .environment(\.flowHeaderAccessory, tabBarClearance > 0
                                         ? AnyView(newDeploymentButton.buttonStyle(.glassCircle).help("새 배포")) : nil)
                            .hidesSystemTitleBar()
                    } else {
                        empty {
                            ContentUnavailableView("아직 배포가 없어요", systemImage: "play",
                                                   description: Text(tabBarClearance > 0 ? "새 배포로 시작해요" : "사이드바의 새 배포로 시작해요"))
                                .emptyStateCentered()
                        }
                    }
                }
            }
        }
        // 가장 최근 배포를 다시 찾아요. 웹 · 다른 기기에서 다시 시도하거나 새로 배포하면 새 배포가 생겨서,
        // 열어 둔 화면이 예전 배포에 머물지 않고 새 배포로 넘어가요 (10/3). 배포 한 건의 상태는 RunView가 따로 받아요.
        // 프로젝트 채널의 `deployment.created`가 오면 바로, 아니면 SSE 15초 · 끊기면 5초마다
        .task(id: app.selectedProjectID) {
            await poll(on: workspace.live.changes, every: { PollInterval.seconds(live: workspace.live.isLive) }) {
                await store.refresh(using: app)
            }
        }
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
