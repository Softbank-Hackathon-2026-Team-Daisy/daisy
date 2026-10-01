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
                        RunView(deploymentID: latest.id).id(latest.id)
                            .toolbar {
                                if tabBarClearance > 0 {
                                    ToolbarItem(placement: .primaryAction) { newDeploymentButton }
                                }
                            }
                    } else {
                        empty {
                            ContentUnavailableView("아직 배포가 없어요", systemImage: "play",
                                                   description: Text(tabBarClearance > 0 ? "새 배포로 시작해요" : "사이드바의 새 배포로 시작해요"))
                        }
                    }
                }
            }
        }
        // 메뉴를 열 때마다 가장 최근 배포를 다시 찾아요 (웹도 들어올 때 한 번 정해요)
        .task(id: app.selectedProjectID) { await store.refresh(using: app) }
    }

    private func empty(@ViewBuilder _ content: () -> some View) -> some View {
        PageScaffold("배포", subtitle: workspace.project.map { "\($0.name)의 배포" }) {
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
