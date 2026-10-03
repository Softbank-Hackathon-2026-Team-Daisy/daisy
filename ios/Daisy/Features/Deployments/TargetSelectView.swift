import SwiftUI

/// W-04 배포할 환경 선택. 여러 환경을 동시에 골라요 (WR-04 목록, WR-05 시작).
/// - 사이드바 "새 배포"로 들어오면: 가장 최근에 빌드된 이미지로 새 배포를 시작해요.
/// - W-03에서 넘어오면: 그 커밋의 이미지로 시작해요.
struct TargetSelectView: View {
    var fixedCommit: String?
    @Environment(AppModel.self) private var app
    @Environment(Router.self) private var router
    @Environment(Workspace.self) private var workspace
    @State private var targets: LoadState<[DeployTarget]> = .idle
    @State private var selected: Set<String> = []
    @State private var latestBuild: Build?
    @State private var starting = false
    @State private var errorMessage: String?
    /// 목록을 받은 프로젝트. 프로젝트를 바꾸면 이전 환경 · 선택 · 빌드를 지우고, 다른 프로젝트로 배포를 시작하지 않아요 (D4 · D6)
    @State private var loadedProject: String?
    /// 처음 받은 뒤 다시 받기 실패 (D15 · X1)
    @State private var refreshError: String?

    init(commit: String? = nil) {
        self.fixedCommit = commit
    }

    private var commit: String? { fixedCommit ?? latestBuild?.commit }
    private var image: String? { latestBuild?.image }

    var body: some View {
        FlowPage(step: 3, title: .app("배포할 환경 선택"),
                 description: .app("여러 환경을 동시에 고를 수 있어요. 같은 이미지(\(commit.map { String($0.prefix(7)) } ?? "—"))가 모든 환경에 배포돼요.")) {
            LoadStateView(state: targets, retry: { await load() }) { targets in
                VStack(alignment: .leading, spacing: 16) {
                    AdaptiveGrid(minimumWidth: 260) {
                        ForEach(targets) { card($0) }
                    }
                    summary(targets)
                    if let errorMessage { InlineAlert(.danger, .app("배포를 시작하지 못했어요"), errorMessage) }
                    if app.isViewer {
                        InlineAlert(.info, .app("읽기 전용 계정이라 배포할 수 없어요."))
                    }
                    FlowButtons {
                        // 웹: 이전 → W-03 이미지 빌드
                        Button("이전") { router.replaceTop(with: commit.map { .build(commit: $0) } ?? .newDeployment) }
                            .buttonStyle(.glassCapsule)
                        Button(starting ? "시작하는 중…" : "인프라 코드 생성 · 검증 시작") {
                            Task { await start(chosenTargets(targets)) }
                        }
                        .buttonStyle(.glassProminent)
                        .disabled(chosenTargets(targets).isEmpty || commit == nil || starting || app.isViewer)
                    }
                }
            }
        }
        .environment(\.flowRefreshIssue, refreshError.map { message in FlowRefreshIssue(message: message) { await load() } })
        // 한 번만 받지 않아요 (D8): 프로젝트 채널 이벤트(`build.received` · `target.status_changed`)가 오면 바로, 아니면 SSE 15초 · 끊기면 5초.
        // 빌드 ID(source_version_id)를 아직 못 받았으면 다음 신호 · 폴링에서 다시 받아요
        .task(id: app.selectedProjectID) {
            await poll(on: workspace.live.changes, every: { PollInterval.seconds(live: workspace.live.isLive) }) { await load() }
        }
    }

    // MARK: 카드

    private func card(_ target: DeployTarget) -> some View {
        let isOn = selected.contains(target.id) && !target.isUnreachable
        return Button {
            if isOn { selected.remove(target.id) } else { selected.insert(target.id) }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isOn ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                        .font(.title3)
                    EnvTag(type: target.type)
                    Spacer()
                }
                Text(target.title ?? target.name).font(.subheadline.weight(.semibold))
                Text(cardDescription(target)).font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardStyle()
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(isOn ? AnyShapeStyle(.tint) : AnyShapeStyle(.clear), lineWidth: 2))
        }
        .buttonStyle(.plain)
        .disabled(target.isUnreachable)
        .opacity(target.isUnreachable ? 0.5 : 1)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    /// 웹: 서버가 준 `reuse.reason`을 그대로 ("home-lab Proxmox VM · 사설망 · 검증된 스크립트 있음 → 태그만 교체").
    /// 연결이 안 되는 환경은 고를 수 없어요.
    private func cardDescription(_ target: DeployTarget) -> String {
        if target.isUnreachable { return .app("연결할 수 없어요 · 환경 화면에서 확인해 주세요") }
        return target.reuse?.reason
            ?? (target.reuse?.available == true ? String.app("검증된 스크립트 있음 → 태그만 교체") : String.app("처음 배포 → AI가 Terraform 생성"))
    }

    // MARK: 선택 요약

    private func summary(_ targets: [DeployTarget]) -> some View {
        let chosen = chosenTargets(targets)
        let reused = chosen.filter { $0.reuse?.available == true }
        let fresh = chosen.filter { $0.reuse?.available != true }
        func names(_ list: [DeployTarget]) -> String {
            list.isEmpty ? String.app("없음") : String.app("\(list.count)개 · \(list.map(\.type.displayName).joined(separator: ", "))")
        }
        return SectionCard(.app("선택 요약")) {
            InfoRow(.app("선택한 환경"), .app("\(chosen.count)개"))
            InfoRow(.app("스크립트 재사용"), names(reused))
            InfoRow(.app("AI가 새로 생성"), names(fresh))
            InfoRow(.app("배포할 이미지"), image ?? "—", monospaced: true)
        }
    }

    /// 고른 환경 중 연결되는 것만 (웹과 같아요)
    private func chosenTargets(_ targets: [DeployTarget]) -> [DeployTarget] {
        targets.filter { selected.contains($0.id) && !$0.isUnreachable }
    }

    // MARK: 동작

    private func load() async {
        guard let client = app.client, let projectID = app.selectedProjectID else { return }
        if loadedProject != projectID {
            (targets, selected, latestBuild, errorMessage, refreshError) = (.idle, [], nil, nil, nil)
            loadedProject = projectID
        }
        if targets.value == nil { targets = .loading }
        // 빌드 목록은 환경 목록과 같이 받아요. 빌드가 실패해도 환경은 보여주고, 시작할 때 다시 받아요
        async let builds = fetchBuilds(client, projectID: projectID)
        do {
            let list = try await client.send(.deployTargets(projectID: projectID)).items
            // 기다리는 동안 프로젝트를 바꿨으면 늦게 온 응답은 버려요
            guard !Task.isCancelled, app.selectedProjectID == projectID else { return }
            // 처음 받을 때만 모두 골라 두고, 그 뒤에는 사용자가 고른 것을 지켜요. 사라진 환경은 빼요
            let ids = Set(list.map(\.id))
            selected = targets.value == nil ? ids : selected.intersection(ids)
            targets = .loaded(list)
            refreshError = nil
        } catch {
            if Task.isCancelled { return }
            app.handle(error)
            // 받아 둔 환경이 있으면 지우지 않고 작게 알려요 (X3)
            if targets.value == nil { targets = .failed(error.localizedDescription) } else { refreshError = error.localizedDescription }
        }
        switch await builds {
        case .success(let latest)?:
            guard app.selectedProjectID == projectID else { return }
            latestBuild = latest.first { build in
                // 같은 커밋을 다시 빌드했을 수 있어서, 커밋을 정해 들어와도 성공한 빌드만 골라요 (서버는 실패 · 진행 중 빌드 ID에 409)
                build.pipeline.status == .success && build.sourceVersionId != nil && (fixedCommit.map { build.commit == $0 } ?? (build.image != nil))
            } ?? latestBuild
        case .failure(let error)?:
            app.handle(error)
            if targets.value != nil { refreshError = error.localizedDescription }
        case nil:
            break
        }
    }

    /// 빌드 목록 (A-06). 취소됐으면 nil
    private func fetchBuilds(_ client: APIClient, projectID: String) async -> Result<[Build], Error>? {
        do {
            return .success(try await client.send(.builds(projectID: projectID)).items)
        } catch {
            return Task.isCancelled ? nil : .failure(error)
        }
    }

    private func start(_ chosen: [DeployTarget]) async {
        // 화면에 보이는 환경을 받은 프로젝트로만 시작해요. 그사이 프로젝트를 바꿨으면 다시 받아요 (D4)
        guard let client = app.client, let projectID = app.selectedProjectID, projectID == loadedProject else {
            await load()
            return
        }
        // 고른 빌드 ID로 시작해요 (필수, #42). 빌드 목록에서 같은 커밋의 빌드를 찾았을 때만 시작할 수 있어요.
        // 아직 못 받았으면 한 번 더 받아 보고 (D8), 그래도 없으면 안내해요
        if latestBuild?.sourceVersionId == nil || latestBuild?.commit != commit { await load() }
        guard let commit, latestBuild?.commit == commit, let build = latestBuild?.sourceVersionId else {
            errorMessage = .app("빌드 정보를 아직 받지 못했어요. 이미지 빌드가 끝난 뒤 다시 시도해 주세요.")
            return
        }
        // 요청을 기다리는 동안 탭을 옮겨도 이 탭에서 열어요 (D13)
        let tab = router.tab
        starting = true
        defer { starting = false }
        do {
            let started = try await client.send(.startDeployment(projectID: projectID, commit: commit,
                                                                 sourceVersionID: build, targetIDs: chosen.map(\.id)))
            errorMessage = nil
            // 배포 탭이면 루트(DeploymentsView)가 `.started`를 이어받아 경로를 비워요 (D12)
            router.replaceTop(with: .started(started.id), in: tab)
            // 사이드바 · 개요 · 배포 목록이 새 배포를 바로 알아요
            workspace.refreshSoon()
        } catch {
            app.handle(error)
            errorMessage = error.localizedDescription
        }
    }
}
