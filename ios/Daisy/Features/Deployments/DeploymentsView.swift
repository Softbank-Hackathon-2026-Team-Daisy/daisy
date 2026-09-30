import SwiftUI

/// 배포 메뉴: 실행 목록. 한 건을 누르면 그 배포의 지금 단계(W-03 ~ W-08)로 들어가요.
/// 승인 대기 건은 위에 따로 모아 보여줘요 (사이드바 "배포" 배지와 같은 건).
struct DeploymentsView: View {
    @Environment(AppModel.self) private var app
    @Environment(Router.self) private var router
    @Environment(Workspace.self) private var workspace
    @State private var store = DeploymentsStore()
    @State private var filter: Filter = .all

    enum Filter: Hashable {
        case all, running, finished

        func includes(_ deployment: Deployment) -> Bool {
            switch self {
            case .all: true
            case .running: !deployment.state.isFinished
            case .finished: deployment.state.isFinished
            }
        }
    }

    var body: some View {
        PageScaffold("배포", subtitle: workspace.project.map { "\($0.name)의 배포 실행" }) {
            GlassSegmented(selection: $filter, items: [
                .init(value: .all, title: "전체"),
                .init(value: .running, title: "진행 중"),
                .init(value: .finished, title: "완료"),
            ])
            Button { router.push(.newDeployment) } label: {
                Label("새 배포", systemImage: "plus")
            }
            .buttonStyle(.glassCapsule)
            .disabled(app.isViewer || workspace.project == nil)
        } content: {
            if app.selectedProjectID == nil {
                NoProjectView()
            } else {
                LoadStateView(state: store.list, retry: { await store.refresh(using: app) }) { all in
                    let deployments = all.filter(filter.includes)
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            if !workspace.awaitingApproval.isEmpty {
                                SectionCard("승인 대기") {
                                    rows(workspace.awaitingApproval, route: { .plan($0.id) })
                                }
                            }
                            SectionCard("실행") {
                                if deployments.isEmpty {
                                    Text("배포 기록이 없어요").foregroundStyle(.secondary)
                                } else {
                                    rows(deployments, route: { .run($0.id) })
                                }
                            }
                        }
                        .padding(20)
                    }
                    .refreshable { await store.refresh(using: app) }
                }
            }
        }
        .task(id: app.selectedProjectID) { await poll { await store.refresh(using: app) } }
    }

    private func rows(_ list: [Deployment], route: @escaping (Deployment) -> Route) -> some View {
        VStack(spacing: 0) {
            ForEach(list) { deployment in
                NavigationLink(value: route(deployment)) {
                    RunListItem(deployment: deployment).padding(.vertical, 8)
                }
                .buttonStyle(.plain)
                if deployment.id != list.last?.id { Divider() }
            }
        }
    }
}
