import SwiftUI

/// W-04 배포할 환경 선택. 여러 환경을 동시에 골라요.
/// - 사이드바 "새 배포"로 들어오면: 가장 최근에 빌드된 이미지로 새 배포를 시작해요.
/// - 배포가 환경 선택 단계에 있으면: 그 배포의 이미지로 이어가요.
struct TargetSelectView: View {
    var deployment: Deployment?
    var onStarted: (() -> Void)?
    @Environment(AppModel.self) private var app
    @Environment(Router.self) private var router
    @Environment(Workspace.self) private var workspace
    @State private var targets: LoadState<[DeployTarget]> = .idle
    @State private var selected: Set<String> = []
    @State private var latestBuild: Build?
    @State private var starting = false
    @State private var errorMessage: String?

    init(deployment: Deployment? = nil, onStarted: (() -> Void)? = nil) {
        self.deployment = deployment
        self.onStarted = onStarted
    }

    private var commit: String? { deployment?.commit ?? latestBuild?.commit }
    private var image: String? { deployment?.image ?? latestBuild?.image }

    var body: some View {
        FlowPage(step: 3, title: "배포할 환경 선택",
                 description: "여러 환경을 동시에 고를 수 있어요. 같은 이미지(\(commit.map { String($0.prefix(7)) } ?? "—"))가 모든 환경에 배포돼요.") {
            LoadStateView(state: targets, retry: { await load() }) { targets in
                VStack(alignment: .leading, spacing: 16) {
                    AdaptiveGrid(minimumWidth: 260) {
                        ForEach(targets) { card($0) }
                    }
                    summary(targets)
                    if let errorMessage { InlineAlert(.danger, "시작하지 못했어요", errorMessage) }
                    if app.isViewer {
                        InlineAlert(.info, "읽기 전용 계정이라 배포할 수 없어요.")
                    }
                    FlowButtons {
                        Button("이전") { router.popToRoot() }
                            .buttonStyle(.glassCapsule)
                        Button {
                            Task { await start() }
                        } label: {
                            if starting { ProgressView().controlSize(.small) } else { Text("인프라 코드 생성 · 검증 시작") }
                        }
                        .buttonStyle(.glassProminent)
                        .disabled(selected.isEmpty || commit == nil || starting || app.isViewer)
                    }
                }
            }
        }
        .task { await load() }
    }

    // MARK: 카드

    private func card(_ target: DeployTarget) -> some View {
        let isOn = selected.contains(target.id)
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
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    /// 웹: "home-lab Proxmox VM · 사설망 · 검증된 스크립트 있음 → 태그만 교체" / "ap-northeast-2 · 처음 배포 → AI가 Terraform 생성"
    private func cardDescription(_ target: DeployTarget) -> String {
        let reuse = target.hasVerifiedScript == true ? "검증된 스크립트 있음 → 태그만 교체" : "처음 배포 → AI가 Terraform 생성"
        return [target.location, reuse].compactMap { $0 }.joined(separator: " · ")
    }

    // MARK: 선택 요약

    private func summary(_ targets: [DeployTarget]) -> some View {
        let chosen = targets.filter { selected.contains($0.id) }
        let reused = chosen.filter { $0.hasVerifiedScript == true }
        let fresh = chosen.filter { $0.hasVerifiedScript != true }
        func names(_ list: [DeployTarget]) -> String {
            list.isEmpty ? "0개" : "\(list.count)개 · " + list.map(\.type.displayName).joined(separator: ", ")
        }
        return SectionCard("선택 요약") {
            InfoRow("선택한 환경", "\(chosen.count)개")
            InfoRow("스크립트 재사용", names(reused))
            InfoRow("AI가 새로 생성", names(fresh))
            InfoRow("배포할 이미지", image, monospaced: true)
        }
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
        if deployment == nil {
            let builds = try? await client.send(.builds(projectID: projectID)).items
            latestBuild = builds?.first { $0.pipeline.status == .success && $0.image != nil }
        }
    }

    private func start() async {
        guard let client = app.client, let projectID = app.selectedProjectID, let commit else { return }
        starting = true
        defer { starting = false }
        do {
            let started = try await client.send(.startDeployment(projectID: projectID, commit: commit, targetIDs: Array(selected)))
            errorMessage = nil
            if let onStarted {
                onStarted()
            } else {
                router.replaceTop(with: .run(started.id))
            }
            await workspace.refresh(using: app)
        } catch {
            app.handle(error)
            errorMessage = error.localizedDescription
        }
    }
}
