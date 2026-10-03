import SwiftUI

/// W-01 개요: 환경별 현재 버전 · 지금 할 일 · 동일성 검증 · 최근 실행.
struct OverviewView: View {
    @Environment(AppModel.self) private var app
    @Environment(Router.self) private var router
    @Environment(Workspace.self) private var workspace
    @State private var store = OverviewStore()
    @State private var projectPickerExpanded = false

    var body: some View {
        PageScaffold(.app("개요"), subtitle: subtitle) {
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
                        StaleBanner(since: store.staleSince)
                        // 넓으면 2:1 두 열, 좁으면 한 열
                        ViewThatFits(in: .horizontal) {
                            HStack(alignment: .top, spacing: 16) {
                                currentVersions.frame(minWidth: 460)
                                todo.frame(width: 340)
                            }
                            .equalCardHeights()
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
        // 프로젝트 · 배포 이벤트(앱 복귀 · 프로젝트 전환 · 승인 포함)가 오면 바로, 아니면 SSE 15초 · 그 밖에 5초.
        // 진행 중이거나 결정이 필요한 배포가 있으면 SSE가 붙어 있어도 5초 (끊기면 2초): 승인 · 배포 상태는 프로젝트 채널에 오지 않아요 (O2)
        .task(id: app.selectedProjectID) {
            await poll(on: workspace.live.changes, every: {
                Freshness.pollSeconds(live: workspace.live.isLive, active: store.hasActive(for: app.selectedProjectID))
            }) { await store.refresh(using: app) }
        }
    }

    /// 웹: "sample-monolith가 지금 어느 환경에 어떤 버전으로 떠 있는지, 다음에 할 일이 뭔지 봐요."
    private var subtitle: String {
        guard let name = workspace.project?.name else { return .app("지금 어느 환경에 어떤 버전으로 떠 있는지, 다음에 할 일이 뭔지 봐요.") }
        return .app("\(name)가 지금 어느 환경에 어떤 버전으로 떠 있는지, 다음에 할 일이 뭔지 봐요.")
    }

    private func refresh() async {
        await workspace.refresh(using: app)
        await store.refresh(using: app)
    }

    // MARK: 환경별 현재 버전

    private var currentVersions: some View {
        SectionCard(.app("환경별 현재 버전")) {
            if let image = workspace.statuses.compactMap({ $0.current?.image }).first {
                Text(image).font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
        } content: {
            if workspace.statuses.isEmpty {
                ContentUnavailableView("아직 배포한 환경이 없어요", systemImage: "server.rack",
                                       description: Text("새 배포로 첫 환경을 올려 보세요"))
                    .emptyStateCentered()
            } else {
                VStack(spacing: 0) {
                    ForEach(workspace.statuses) { status in
                        VersionRow(status: status)
                        if status.id != workspace.statuses.last?.id { Divider() }
                    }
                }
                let matching = workspace.statuses.parityMatching
                HStack(spacing: 8) {
                    StatusBadge(text: .app("\(matching)/\(workspace.statuses.count) 일치"),
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

    /// 이 프로젝트의 A-03 한 응답에서 만든 할 일 · 최근 실행 (O4). 다른 프로젝트 것이면 로딩이에요 (O3)
    private var board: LoadState<OverviewStore.Board> { store.state(for: app.selectedProjectID) }

    /// 가장 최근 배포이고 아직 승인 안 된 환경이 있을 때만 할 일이에요. 이미 승인했거나 버려진 배포의 plan을 열지 않아요 (O1)
    private var todo: some View {
        SectionCard(.app("지금 할 일")) {
            if case .failed(let message) = board {
                InlineAlert(.warning, .app("불러오지 못했어요"), message)
            } else if board.value == nil {
                ProgressView().frame(maxWidth: .infinity, minHeight: 80)
            } else if let waiting = board.value?.todo {
                VStack(alignment: .leading, spacing: 12) {
                    Button {
                        router.push(.plan(waiting.id))
                    } label: {
                        RunListItem(deployment: waiting)
                    }
                    .buttonStyle(.plain)
                    InlineAlert(.info, .app("검증 통과 · 승인만 남았어요"), reuseNote(waiting))
                    Button("plan 보고 승인하기") { router.push(.plan(waiting.id)) }
                        .buttonStyle(.glassCapsule(fullWidth: true))
                }
            } else {
                // 카드 폭이 넓어도(한 열 배치) 안내는 늘 카드 가운데에 와요 (10/2 담당자 요청)
                ContentUnavailableView("지금 할 일이 없어요", systemImage: "checkmark",
                                       description: Text("승인을 기다리는 배포가 없어요"))
                    .emptyStateCentered()
            }
        }
    }

    /// "온프레미스는 검증된 스크립트 재사용이라 AI 호출 0회예요."
    private func reuseNote(_ deployment: Deployment) -> String? {
        let reused = (deployment.targets ?? []).filter { $0.reusedScript == true }
        guard !reused.isEmpty else { return .app("모든 환경의 validate · plan · 위험 설정 검사를 통과했어요.") }
        let names = reused.map { target in
            workspace.statuses.first { $0.targetId == target.targetId }?.type.displayName ?? target.targetId
        }
        return .app("\(names.joined(separator: " · "))는 검증된 스크립트 재사용이라 AI 호출 0회예요.")
    }

    // MARK: 최근 실행

    private var recentRuns: some View {
        SectionCard(.app("최근 실행")) {
            Button("이력 전체 보기") { router.tab = .history }
                .buttonStyle(.glassCapsule)
        } content: {
            switch board {
            case .idle, .loading:
                ProgressView().frame(maxWidth: .infinity, minHeight: 60)
            case .failed(let message):
                Text(message).foregroundStyle(.secondary)
            case .loaded(let board) where board.recent.isEmpty:
                Text("아직 실행한 배포가 없어요").foregroundStyle(.secondary)
            case .loaded(let board):
                VStack(spacing: 0) {
                    ForEach(board.recent) { deployment in
                        NavigationLink(value: Route.run(deployment.id)) {
                            RunListItem(deployment: deployment, badge: recentBadge(deployment, newestID: board.newestID)).padding(.vertical, 8)
                        }
                        .buttonStyle(.plain)
                        if deployment.id != board.recent.last?.id { Divider() }
                    }
                }
            }
        }
    }

    /// 웹 최근 실행: 성공은 "배포 완료", 실패는 "중단", 나머지는 상태 그대로.
    /// 승인 대기로 남은 지난 배포는 "승인 대기 (지난 배포)", 승인하고 실행만 기다리면 "승인 완료 · 실행 대기"
    private func recentBadge(_ deployment: Deployment, newestID: String?) -> StatusBadge {
        switch deployment.state {
        case .succeeded where !deployment.isRollback: StatusBadge(text: .app("배포 완료"), color: .green)
        case .failed: StatusBadge(text: .app("중단"), color: .red)
        default: deployment.listBadge(newestID: newestID)
        }
    }

    // MARK: 프로젝트 · 빈 상태

    /// 좁은 화면에는 사이드바가 없어서 여기서 프로젝트를 바꿔요. 평소엔 폴더 원 버튼, 누르면 이름이 펼쳐지고, 한 번 더 누르면 목록 (10/3)
    @ViewBuilder
    private var projectMenu: some View {
        if !workspace.projects.isEmpty {
            ExpandingMenuButton(systemImage: "folder", title: workspace.project?.name ?? String.app("프로젝트"),
                                isExpanded: $projectPickerExpanded,
                                options: workspace.projects.map { project in
                                    ExpandingMenuOption(id: project.id, title: project.name, isSelected: project.id == app.selectedProjectID) {
                                        app.selectedProjectID = project.id
                                        Task { await refresh() }
                                    }
                                } + [ExpandingMenuOption(id: "connect", title: .app("새 프로젝트 연결"), systemImage: "plus",
                                                         isDisabled: app.isViewer, separated: true) { router.open(.connectProject) }])
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
        .emptyStateCentered()
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
