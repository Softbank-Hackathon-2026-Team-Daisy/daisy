import SwiftUI

/// W-01 개요: 환경별 현재 버전 · 지금 할 일 · 동일성 검증 · 최근 실행.
struct OverviewView: View {
    @Environment(AppModel.self) private var app
    @Environment(Router.self) private var router
    @Environment(Workspace.self) private var workspace
    @State private var store = OverviewStore()

    var body: some View {
        PageScaffold("개요", subtitle: subtitle) {
            projectMenu
            Button { Task { await refresh() } } label: {
                Label("새로 고침", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.glassCircle)
            .help("새로 고침")
        } content: {
            if workspace.projects.isEmpty && workspace.loadedOnce {
                empty
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // 넓으면 2:1 두 열, 좁으면 한 열
                        ViewThatFits(in: .horizontal) {
                            HStack(alignment: .top, spacing: 16) {
                                currentVersions.frame(minWidth: 460)
                                todo.frame(width: 340)
                            }
                            VStack(spacing: 16) { currentVersions; todo }
                        }
                        if !workspace.statuses.isEmpty {
                            ParityTable(parity: Parity(statuses: workspace.statuses), targets: workspace.statuses.map(\.type))
                        }
                        recentRuns
                    }
                    .padding(20)
                }
                .refreshable { await refresh() }
            }
        }
        .task(id: app.selectedProjectID) { await poll { await store.refresh(using: app) } }
    }

    /// 웹: "sample-monolith가 지금 어느 환경에 어떤 버전으로 떠 있는지, 다음에 할 일이 뭔지 봐요."
    private var subtitle: String {
        (workspace.project.map { "\($0.name)가 " } ?? "") + "지금 어느 환경에 어떤 버전으로 떠 있는지, 다음에 할 일이 뭔지 봐요."
    }

    private func refresh() async {
        await workspace.refresh(using: app)
        await store.refresh(using: app)
    }

    // MARK: 환경별 현재 버전

    private var currentVersions: some View {
        SectionCard("환경별 현재 버전") {
            if let image = workspace.statuses.compactMap({ $0.current?.image }).first {
                Text(image).font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
        } content: {
            if workspace.statuses.isEmpty {
                ContentUnavailableView("아직 배포한 환경이 없어요", systemImage: "server.rack",
                                       description: Text("새 배포로 첫 환경을 올려 보세요"))
            } else {
                VStack(spacing: 0) {
                    ForEach(workspace.statuses) { status in
                        VersionRow(status: status)
                        if status.id != workspace.statuses.last?.id { Divider() }
                    }
                }
                let matching = workspace.statuses.parityMatching
                HStack(spacing: 8) {
                    StatusBadge(text: "\(matching)/\(workspace.statuses.count) 일치",
                                color: matching == workspace.statuses.count ? .green : .orange)
                    Text(matching == workspace.statuses.count
                         ? "\(koreanCount(workspace.statuses.count)) 환경 모두 같은 이미지 digest예요"
                         : "이미지 digest가 다른 환경이 있어요")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: 지금 할 일

    private var todo: some View {
        SectionCard("지금 할 일") {
            if let waiting = workspace.awaitingApproval.first {
                VStack(alignment: .leading, spacing: 12) {
                    Button {
                        router.push(.plan(waiting.id))
                    } label: {
                        RunListItem(deployment: waiting)
                    }
                    .buttonStyle(.plain)
                    InlineAlert(.info, "검증 통과 · 승인만 남았어요", reuseNote(waiting))
                    Button("plan 보고 승인하기") { router.push(.plan(waiting.id)) }
                        .buttonStyle(.glassCapsule(fullWidth: true))
                }
            } else {
                // 카드 폭이 넓어도(한 열 배치) 안내는 늘 카드 가운데에 와요 (10/2 담당자 요청)
                ContentUnavailableView("지금 할 일이 없어요", systemImage: "checkmark",
                                       description: Text("승인을 기다리는 배포가 없어요"))
                    .frame(maxWidth: .infinity)
            }
        }
    }

    /// "온프레미스는 검증된 스크립트 재사용이라 AI 호출 0회예요."
    private func reuseNote(_ deployment: Deployment) -> String? {
        let reused = (deployment.targets ?? []).filter { $0.reusedScript == true }
        guard !reused.isEmpty else { return "모든 환경의 validate · plan · 위험 설정 검사를 통과했어요." }
        let names = reused.map { target in
            workspace.statuses.first { $0.targetId == target.targetId }?.type.displayName ?? target.targetId
        }
        return "\(names.joined(separator: " · "))는 검증된 스크립트 재사용이라 AI 호출 0회예요."
    }

    // MARK: 최근 실행

    private var recentRuns: some View {
        SectionCard("최근 실행") {
            Button("이력 전체 보기") { router.tab = .history }
                .buttonStyle(.glassCapsule)
        } content: {
            if store.recent.isEmpty {
                Text("아직 실행한 배포가 없어요").foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(store.recent) { deployment in
                        NavigationLink(value: Route.run(deployment.id)) {
                            RunListItem(deployment: deployment, badge: recentBadge(deployment)).padding(.vertical, 8)
                        }
                        .buttonStyle(.plain)
                        if deployment.id != store.recent.last?.id { Divider() }
                    }
                }
            }
        }
    }

    /// 웹 최근 실행: 성공은 "배포 완료", 실패는 "중단", 나머지는 상태 그대로
    private func recentBadge(_ deployment: Deployment) -> StatusBadge {
        switch deployment.state {
        case .succeeded where !deployment.isRollback: StatusBadge(text: "배포 완료", color: .green)
        case .failed: StatusBadge(text: "중단", color: .red)
        default: deployment.badge
        }
    }

    // MARK: 프로젝트 · 빈 상태

    /// 좁은 화면에는 사이드바가 없어서 여기서 프로젝트를 바꿔요.
    @ViewBuilder
    private var projectMenu: some View {
        if !workspace.projects.isEmpty {
            Menu {
                Picker("프로젝트", selection: Binding(
                    get: { app.selectedProjectID ?? "" },
                    set: { app.selectedProjectID = $0; Task { await refresh() } }
                )) {
                    ForEach(workspace.projects) { Text($0.name).tag($0.id) }
                }
                Divider()
                Button { router.open(.connectProject) } label: { Label("새 프로젝트 연결", systemImage: "plus") }
                    .disabled(app.isViewer)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "folder")
                    Text(workspace.project?.name ?? "프로젝트")
                    Image(systemName: "chevron.down").font(.caption2.weight(.semibold))
                }
            }
            .menuStyle(.button)
            .menuIndicator(.hidden)
            .buttonStyle(.glassCapsule)
            .fixedSize()
        }
    }

    /// 웹 Empty State: "아직 배포한 프로젝트가 없어요"
    private var empty: some View {
        ContentUnavailableView {
            Label("아직 배포한 프로젝트가 없어요", systemImage: "shippingbox")
        } description: {
            Text("GitHub 레포를 연결해서 시작해 보세요")
        } actions: {
            Button("새 프로젝트") { router.open(.connectProject) }
                .buttonStyle(.glassCapsule(prominent: true))
                .disabled(app.isViewer)
        }
    }
}

/// 환경 한 줄: 환경 태그 · 커밋 · 시각 · URL · 상태.
private struct VersionRow: View {
    let status: TargetStatus

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                EnvTag(type: status.type).frame(width: 100, alignment: .leading)
                details
                Spacer(minLength: 8)
                status.health.badge
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack { EnvTag(type: status.type); Spacer(); status.health.badge }
                details
            }
        }
        .padding(.vertical, 10)
    }

    private var details: some View {
        HStack(spacing: 10) {
            if let current = status.current {
                CommitLabel(commit: current.commit)
                if let deployedAt = current.deployedAt {
                    RelativeTime(date: deployedAt).font(.caption).foregroundStyle(.secondary)
                }
            } else {
                // null은 "배포 없음"이 아니라 "확인된 현재 배포 없음"이에요 (10/2 01:10 서버 #42 요청)
                Text(status.currentStatus == .unverified ? "현재 배포를 확인하지 못했어요" : "확인된 배포 없음")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let url = status.url {
                Link(url.absoluteString, destination: url).font(.caption).lineLimit(1).truncationMode(.middle)
            }
        }
    }
}
