import SwiftUI

/// 2 배포 목록 (A-03, 서버 D3 제공).
struct DeploymentsView: View {
    @Environment(AppModel.self) private var app
    @State private var store = DeploymentsStore()

    var body: some View {
        Group {
            if app.client == nil {
                NotConnectedView()
            } else if app.selectedProjectID == nil {
                NoProjectView()
            } else {
                LoadStateView(state: store.list, retry: { await store.refresh(using: app) }) { deployments in
                    List(deployments) { deployment in
                        NavigationLink(value: deployment.id) { DeploymentRow(deployment: deployment) }
                    }
                    .overlay {
                        if deployments.isEmpty {
                            ContentUnavailableView("배포 기록이 없어요", systemImage: "tray")
                        }
                    }
                    .refreshable { await store.refresh(using: app) }
                }
            }
        }
        .navigationTitle("배포")
        .navigationDestination(for: String.self) { DeploymentDetailView(deploymentID: $0) }
        .task(id: app.selectedProjectID) { await poll { await store.refresh(using: app) } }
    }
}

struct DeploymentRow: View {
    let deployment: Deployment

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                CommitLabel(commit: deployment.commit)
                HStack(spacing: 6) {
                    Text("\(deployment.targets?.count ?? 0)개 환경")
                    if let createdAt = deployment.createdAt {
                        Text(createdAt, format: .relative(presentation: .named))
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            deployment.state.badge
        }
    }
}
