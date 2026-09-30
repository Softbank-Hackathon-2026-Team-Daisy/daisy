import SwiftUI

/// 2 배포 목록 (A-03, 서버 D3 제공).
struct DeploymentsView: View {
    @Environment(AppModel.self) private var app
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
        PageScaffold("배포") {
            GlassSegmented(selection: $filter, items: [
                .init(value: .all, title: "전체"),
                .init(value: .running, title: "진행 중"),
                .init(value: .finished, title: "완료"),
            ])
            Button { Task { await store.refresh(using: app) } } label: {
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
                LoadStateView(state: store.list, retry: { await store.refresh(using: app) }) { all in
                    let deployments = all.filter(filter.includes)
                    List(deployments) { deployment in
                        NavigationLink(value: deployment.id) { DeploymentRow(deployment: deployment) }
                    }
                    .overlay {
                        if deployments.isEmpty {
                            ContentUnavailableView("배포 기록이 없어요", systemImage: "tray")
                        }
                    }
                    .onContentSurface()
                    .refreshable { await store.refresh(using: app) }
                }
            }
        }
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
