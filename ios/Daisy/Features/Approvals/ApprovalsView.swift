import SwiftUI

/// 4 승인 목록. A-08 대신 배포 목록(A-03)을 `awaiting_approval`로 걸러요 (9/29 합의).
struct ApprovalsView: View {
    @Environment(AppModel.self) private var app
    @State private var store = DeploymentsStore()

    var body: some View {
        PageScaffold("승인", subtitle: "사람이 확인해야 배포돼요") {
            Button { Task { await refresh() } } label: {
                Label("새로 고침", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.glassCircle)
            .help("새로 고침")
        } content: {
            if app.client == nil {
                NotConnectedView()
            } else if app.selectedProjectID == nil {
                NoProjectView()
            } else {
                LoadStateView(state: store.list, retry: { await refresh() }) { deployments in
                    List(deployments) { deployment in
                        NavigationLink(value: deployment.id) { DeploymentRow(deployment: deployment) }
                    }
                    .overlay {
                        if deployments.isEmpty {
                            ContentUnavailableView("승인할 plan이 없어요", systemImage: "checkmark.seal")
                        }
                    }
                    .onContentSurface()
                    .refreshable { await refresh() }
                }
            }
        }
        .navigationDestination(for: String.self) { PlanApprovalView(deploymentID: $0) }
        .task(id: app.selectedProjectID) { await poll { await refresh() } }
    }

    private func refresh() async {
        await store.refresh(using: app, state: .awaitingApproval)
    }
}
