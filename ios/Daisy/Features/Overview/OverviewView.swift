import SwiftUI

/// 1 현황: 어느 환경에 어떤 커밋이 떠 있는지 (SPEC §2).
struct OverviewView: View {
    @Environment(AppModel.self) private var app
    @State private var store = OverviewStore()

    var body: some View {
        Group {
            if app.client == nil {
                NotConnectedView()
            } else {
                LoadStateView(state: store.statuses, retry: { await store.refreshStatuses(using: app) }) { statuses in
                    list(statuses)
                }
            }
        }
        .navigationTitle("현황")
        .toolbar { projectPicker }
        .task(id: app.client == nil) { await store.loadProjects(using: app) }
        .task(id: app.selectedProjectID) {
            store.reset()
            await poll { await store.refreshStatuses(using: app) }
        }
    }

    private func list(_ statuses: [TargetStatus]) -> some View {
        List {
            if !statuses.isEmpty {
                Section { consistencyRow(statuses) }
            }
            Section("환경") {
                if statuses.isEmpty {
                    Text("아직 등록된 환경이 없어요.").foregroundStyle(.secondary)
                }
                ForEach(statuses) { status in
                    if let deploymentID = status.current?.deploymentId {
                        NavigationLink(value: deploymentID) { TargetStatusRow(status: status) }
                    } else {
                        TargetStatusRow(status: status)
                    }
                }
            }
        }
        .refreshable { await store.refreshStatuses(using: app) }
        .navigationDestination(for: String.self) { DeploymentDetailView(deploymentID: $0) }
    }

    @ViewBuilder
    private func consistencyRow(_ statuses: [TargetStatus]) -> some View {
        if statuses.isConsistent, let commit = statuses.deployedCommits.first {
            Label {
                HStack {
                    Text("모든 환경이 같은 버전이에요")
                    Spacer()
                    CommitLabel(commit: commit)
                }
            } icon: {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            }
        } else if !statuses.isConsistent {
            Label {
                Text("환경마다 버전이 달라요 (\(statuses.deployedCommits.count)개 커밋)")
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            }
        }
    }

    @ToolbarContentBuilder
    private var projectPicker: some ToolbarContent {
        if let projects = store.projects.value, !projects.isEmpty {
            ToolbarItem {
                Picker("프로젝트", selection: Binding(
                    get: { app.selectedProjectID ?? "" },
                    set: { app.selectedProjectID = $0 }
                )) {
                    ForEach(projects) { Text($0.name).tag($0.id) }
                }
            }
        }
    }
}

struct TargetStatusRow: View {
    let status: TargetStatus

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            EnvironmentIcon(type: status.type)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(status.name).font(.headline)
                    Text(status.type.displayName).font(.caption).foregroundStyle(.secondary)
                }
                if let current = status.current {
                    HStack(spacing: 6) {
                        CommitLabel(commit: current.commit)
                        if let deployedAt = current.deployedAt {
                            Text(deployedAt, format: .relative(presentation: .named))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    Text("아직 배포되지 않았어요").font(.caption).foregroundStyle(.secondary)
                }
                if let url = status.url {
                    Link(url.host() ?? url.absoluteString, destination: url).font(.caption)
                }
            }
            Spacer()
            status.health.badge
        }
    }
}
