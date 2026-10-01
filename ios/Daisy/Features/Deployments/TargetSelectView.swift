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

    init(commit: String? = nil) {
        self.fixedCommit = commit
    }

    private var commit: String? { fixedCommit ?? latestBuild?.commit }
    private var image: String? { latestBuild?.image }

    var body: some View {
        FlowPage(step: 3, title: "배포할 환경 선택",
                 description: "여러 환경을 동시에 고를 수 있어요. 같은 이미지(\(commit.map { String($0.prefix(7)) } ?? "—"))가 모든 환경에 배포돼요.") {
            LoadStateView(state: targets, retry: { await load() }) { targets in
                VStack(alignment: .leading, spacing: 16) {
                    AdaptiveGrid(minimumWidth: 260) {
                        ForEach(targets) { card($0) }
                    }
                    summary(targets)
                    if let errorMessage { InlineAlert(.danger, "배포를 시작하지 못했어요", errorMessage) }
                    if app.isViewer {
                        InlineAlert(.info, "읽기 전용 계정이라 배포할 수 없어요.")
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
        .task { await load() }
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
        if target.isUnreachable { return "연결할 수 없어요 · 환경 화면에서 확인해 주세요" }
        return target.reuse?.reason
            ?? (target.reuse?.available == true ? "검증된 스크립트 있음 → 태그만 교체" : "처음 배포 → AI가 Terraform 생성")
    }

    // MARK: 선택 요약

    private func summary(_ targets: [DeployTarget]) -> some View {
        let chosen = chosenTargets(targets)
        let reused = chosen.filter { $0.reuse?.available == true }
        let fresh = chosen.filter { $0.reuse?.available != true }
        func names(_ list: [DeployTarget]) -> String {
            list.isEmpty ? "없음" : "\(list.count)개 · " + list.map(\.type.displayName).joined(separator: ", ")
        }
        return SectionCard("선택 요약") {
            InfoRow("선택한 환경", "\(chosen.count)개")
            InfoRow("스크립트 재사용", names(reused))
            InfoRow("AI가 새로 생성", names(fresh))
            InfoRow("배포할 이미지", image ?? "—", monospaced: true)
        }
    }

    /// 고른 환경 중 연결되는 것만 (웹과 같아요)
    private func chosenTargets(_ targets: [DeployTarget]) -> [DeployTarget] {
        targets.filter { selected.contains($0.id) && !$0.isUnreachable }
    }

    // MARK: 동작

    private func load() async {
        guard let client = app.client, let projectID = app.selectedProjectID else { return }
        if targets.value == nil { targets = .loading }
        do {
            let list = try await client.send(.deployTargets(projectID: projectID)).items
            targets = .loaded(list)
            if selected.isEmpty { selected = Set(list.map(\.id)) }
        } catch {
            app.handle(error)
            targets = .failed(error.localizedDescription)
        }
        let builds = try? await client.send(.builds(projectID: projectID)).items
        latestBuild = builds?.first { build in
            fixedCommit.map { build.commit == $0 } ?? (build.pipeline.status == .success && build.image != nil)
        }
    }

    private func start(_ chosen: [DeployTarget]) async {
        guard let client = app.client, let projectID = app.selectedProjectID, let commit else { return }
        starting = true
        defer { starting = false }
        do {
            let started = try await client.send(.startDeployment(projectID: projectID, commit: commit, targetIDs: chosen.map(\.id)))
            errorMessage = nil
            router.replaceTop(with: .started(started.id))
            await workspace.refresh(using: app)
        } catch {
            app.handle(error)
            errorMessage = error.localizedDescription
        }
    }
}
