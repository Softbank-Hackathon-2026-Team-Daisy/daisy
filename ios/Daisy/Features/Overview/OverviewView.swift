import SwiftUI

/// 1 현황: 어느 환경에 어떤 커밋이 떠 있는지 (SPEC §2).
struct OverviewView: View {
    @Environment(AppModel.self) private var app
    @State private var store = OverviewStore()

    var body: some View {
        PageScaffold("현황", subtitle: "환경마다 지금 떠 있는 버전") {
            if app.client != nil {
                projectMenu
                Button { Task { await store.refreshStatuses(using: app) } } label: {
                    Label("새로 고침", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.glassCircle)
                .help("새로 고침")
            }
        } content: {
            if app.client == nil {
                NotConnectedView()
            } else {
                LoadStateView(state: store.statuses, retry: { await store.refreshStatuses(using: app) }) { statuses in
                    list(statuses)
                }
            }
        }
        .task(id: app.client == nil) { await store.loadProjects(using: app) }
        .task(id: app.selectedProjectID) {
            store.reset()
            await poll { await store.refreshStatuses(using: app) }
        }
    }

    /// 폰은 카드 1열, iPad · Mac은 환경 카드가 가로로 나란히 (온프레미스 · AWS · GCP 한눈에).
    private func list(_ statuses: [TargetStatus]) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if !statuses.isEmpty {
                    consistencyRow(statuses).cardStyle()
                }
                if statuses.isEmpty {
                    ContentUnavailableView("아직 등록된 환경이 없어요", systemImage: "server.rack")
                }
                AdaptiveGrid {
                    ForEach(statuses) { status in
                        if let deploymentID = status.current?.deploymentId {
                            NavigationLink(value: deploymentID) { TargetStatusCard(status: status) }
                                .buttonStyle(.plain)
                        } else {
                            TargetStatusCard(status: status)
                        }
                    }
                }
            }
            .padding()
        }
        .refreshable { await store.refreshStatuses(using: app) }
        .navigationDestination(for: String.self) { DeploymentDetailView(deploymentID: $0) }
    }

    /// 배포된 환경이 모두 같은 커밋인지. 이식성을 한 줄로 보여줘요.
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
        } else if statuses.isConsistent {
            Label("아직 배포된 환경이 없어요", systemImage: "circle.dashed")
                .foregroundStyle(.secondary)
        } else {
            Label {
                Text("환경마다 버전이 달라요 (\(statuses.deployedCommits.count)개 커밋)")
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            }
        }
    }

    /// Craft의 캡슐 버튼 모양으로 프로젝트를 골라요.
    @ViewBuilder
    private var projectMenu: some View {
        if let projects = store.projects.value, !projects.isEmpty {
            Menu {
                Picker("프로젝트", selection: Binding(
                    get: { app.selectedProjectID ?? "" },
                    set: { app.selectedProjectID = $0 }
                )) {
                    ForEach(projects) { Text($0.name).tag($0.id) }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "folder")
                    Text(projects.first { $0.id == app.selectedProjectID }?.name ?? "프로젝트")
                    Image(systemName: "chevron.down").font(.caption2.weight(.semibold))
                }
            }
            .menuStyle(.button)
            .menuIndicator(.hidden)
            .buttonStyle(.glassCapsule)
            .fixedSize()
        }
    }
}

struct TargetStatusCard: View {
    let status: TargetStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                EnvironmentIcon(type: status.type)
                VStack(alignment: .leading) {
                    Text(status.name).font(.headline)
                    Text(status.type.displayName).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                status.health.badge
            }
            Divider()
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
        .cardStyle()
        .contentShape(.rect)
    }
}
