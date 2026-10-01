import SwiftUI

/// W-09 배포 이력: 버전 · 커밋 · 상태 · 환경 · 배포자 · 시간 · 동작(승인하기 · 롤백 · 결과).
/// 넓으면 표, 좁으면 목록 (도영 님 메모). 롤백(WR-14)은 새 배포 한 건이고 plan 승인을 거쳐요.
struct HistoryView: View {
    @Environment(AppModel.self) private var app
    @Environment(Router.self) private var router
    @Environment(Workspace.self) private var workspace
    @State private var store = DeploymentsStore()
    @State private var rollbackTarget: Deployment?
    @State private var toast: ToastMessage?

    var body: some View {
        PageScaffold("배포 이력", subtitle: "버전마다 어떤 이미지와 스크립트로 어느 환경에 배포했는지 남겨요.") {
            Button { Task { await store.refresh(using: app) } } label: {
                Label("새로 고침", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.glassCircle)
            .help("새로 고침")
        } content: {
            if app.selectedProjectID == nil {
                NoProjectView()
            } else {
                LoadStateView(state: store.list, retry: { await store.refresh(using: app) }) { deployments in
                    ScrollView {
                        SectionCard(workspace.project?.name ?? "배포") {
                            if deployments.isEmpty {
                                ContentUnavailableView("아직 배포 이력이 없어요", systemImage: "clock",
                                                       description: Text("첫 배포를 하면 여기에 쌓여요"))
                            } else {
                                ViewThatFits(in: .horizontal) {
                                    table(deployments).frame(minWidth: 760)
                                    list(deployments)
                                }
                            }
                        }
                        .padding(20)
                    }
                    .refreshable { await store.refresh(using: app) }
                }
            }
        }
        .task(id: app.selectedProjectID) { await store.refresh(using: app) }
        .toast($toast)
        .sheet(item: $rollbackTarget) { deployment in
            RollbackDialog(deployment: deployment, projectName: workspace.project?.name ?? "",
                           name: { workspace.name(of: $0) }) { targetIDs in
                try await rollback(deployment, targetIDs: targetIDs)
            }
        }
    }

    // MARK: 표 · 목록

    private func table(_ deployments: [Deployment]) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 12) {
            GridRow {
                Text("버전"); Text("커밋"); Text("상태"); Text("환경"); Text("배포자"); Text("시간"); Text("")
            }
            .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Divider()
            ForEach(deployments) { deployment in
                GridRow {
                    versionText(deployment).font(.subheadline.monospaced())
                    NavigationLink(value: Route.run(deployment.id)) { CommitLabel(commit: deployment.commit) }
                        .buttonStyle(.plain)
                    statusBadge(deployment)
                    environmentTags(deployment)
                    HStack(spacing: 6) { Avatar(name: deployment.createdBy); Text(deployment.createdBy ?? "—").font(.subheadline) }
                    timeText(deployment).font(.caption).foregroundStyle(.secondary)
                    actionButton(deployment, latestSucceeded: deployments.first { $0.state == .succeeded }?.id)
                }
            }
        }
    }

    private func list(_ deployments: [Deployment]) -> some View {
        VStack(spacing: 0) {
            ForEach(deployments) { deployment in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        versionText(deployment).font(.subheadline.monospaced().weight(.semibold))
                        CommitLabel(commit: deployment.commit)
                        Spacer()
                        statusBadge(deployment)
                    }
                    environmentTags(deployment)
                    HStack {
                        Avatar(name: deployment.createdBy)
                        Text(deployment.createdBy ?? "—").font(.caption)
                        timeText(deployment).font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        actionButton(deployment, latestSucceeded: deployments.first { $0.state == .succeeded }?.id)
                    }
                }
                .padding(.vertical, 10)
                if deployment.id != deployments.last?.id { Divider() }
            }
        }
    }

    /// 롤백 배포도 일반 배포처럼 보여줘요 (9/30 도영 님)
    private func versionText(_ deployment: Deployment) -> Text {
        Text(deployment.version ?? "—")
    }

    private func environmentTags(_ deployment: Deployment) -> some View {
        HStack(spacing: 4) {
            ForEach(deployment.targets ?? []) { EnvTag(type: workspace.type(of: $0.targetId)) }
        }
    }

    /// 웹: 롤백 배포는 "롤백 · 성공"처럼 앞에 붙여요
    private func statusBadge(_ deployment: Deployment) -> StatusBadge {
        let badge = deployment.badge
        // 성공한 롤백은 이미 "롤백됨"이라 앞에 붙이지 않아요 ("롤백 · 롤백됨" 방지)
        guard deployment.isRollback, badge.text != "롤백됨" else { return badge }
        return StatusBadge(text: "롤백 · \(badge.text)", color: badge.color)
    }

    /// 웹: "10:12 · 12분 전" (만든 시각 기준)
    private func timeText(_ deployment: Deployment) -> some View {
        Group {
            if let date = deployment.createdAt {
                HStack(spacing: 4) {
                    Text(TimeText.clock(date))
                    Text("·")
                    RelativeTime(date: date)
                }
            } else {
                Text("—")
            }
        }
    }

    /// 웹: 승인 대기 → "승인하기"(W-06), 가장 최근 성공이 아닌 성공 배포 → "롤백", 나머지 → "결과"(W-08)
    @ViewBuilder
    private func actionButton(_ deployment: Deployment, latestSucceeded: String?) -> some View {
        if deployment.state == .awaitingApproval {
            Button("승인하기") { router.push(.plan(deployment.id)) }
                .buttonStyle(.glassCapsule)
        } else if deployment.state == .succeeded && deployment.id != latestSucceeded {
            Button("롤백") { rollbackTarget = deployment }
                .buttonStyle(.glassCapsule)
                .disabled(app.isViewer)
        } else {
            Button("결과") { router.push(.run(deployment.id)) }
                .buttonStyle(.glassCapsule)
        }
    }

    // MARK: 롤백

    /// 고른 환경만 되돌리는 새 배포를 만들고 L-02 → W-05로 가요 (웹과 같아요)
    private func rollback(_ deployment: Deployment, targetIDs: [String]) async throws {
        guard let client = app.client else { return }
        do {
            let next = try await client.send(.rollback(deploymentID: deployment.id, targetIDs: targetIDs,
                                                       reason: "\(deployment.version ?? String(deployment.commit.prefix(7)))로 롤백"))
            rollbackTarget = nil
            router.push(.started(next.id))
        } catch {
            app.handle(error)
            throw error
        }
    }
}

/// 웹 Dialog: "v6로 롤백 배포를 시작할까요?" + 환경 체크 + 프로젝트 이름 입력 + 취소 · 롤백 배포 시작
struct RollbackDialog: View {
    let deployment: Deployment
    let projectName: String
    let name: (String) -> String
    let onConfirm: ([String]) async throws -> Void
    @State private var picked: Set<String>
    @State private var confirm = ""
    @State private var pending = false
    @State private var errorMessage: String?
    @Environment(\.dismiss) private var dismiss

    init(deployment: Deployment, projectName: String, name: @escaping (String) -> String,
         onConfirm: @escaping ([String]) async throws -> Void) {
        self.deployment = deployment
        self.projectName = projectName
        self.name = name
        self.onConfirm = onConfirm
        _picked = State(initialValue: Set((deployment.targets ?? []).map(\.targetId)))
    }

    private var version: String { deployment.version ?? String(deployment.commit.prefix(7)) }
    private var chosen: [String] { (deployment.targets ?? []).map(\.targetId).filter { picked.contains($0) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("\(version)로 롤백 배포를 시작할까요?", systemImage: "arrow.counterclockwise").font(.headline)
                Spacer()
                Button { dismiss() } label: { Label("닫기", systemImage: "xmark") }
                    .buttonStyle(GlassCircleButtonStyle(diameter: 28))
            }
            let names = chosen.isEmpty ? "고른 환경" : FlowCopy.join(chosen.map(name))
            Text("\(version)(\(deployment.commit.prefix(7))) 이미지로 새 배포를 만들어서 \(names)에 다시 올려요. 검증된 스크립트를 재사용해서 AI는 부르지 않아요. plan을 확인하고 승인해야 적용돼요.")
                .font(.subheadline).foregroundStyle(.secondary)
            HStack(spacing: 16) {
                // 체크박스 (iOS에는 체크박스 스타일이 없어서 아이콘 버튼으로)
                ForEach(deployment.targets ?? []) { target in
                    let isOn = picked.contains(target.targetId)
                    Button {
                        if isOn { picked.remove(target.targetId) } else { picked.insert(target.targetId) }
                    } label: {
                        Label(name(target.targetId), systemImage: isOn ? "checkmark.square.fill" : "square")
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isOn ? .isSelected : [])
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("확인을 위해 프로젝트 이름(\(projectName))을 입력해 주세요.").font(.caption).foregroundStyle(.secondary)
                TextField(projectName, text: $confirm)
                    .textFieldStyle(.roundedBorder)
                    .plainInput()
            }
            if let errorMessage { InlineAlert(.danger, "롤백을 시작하지 못했어요", errorMessage) }
            HStack {
                Spacer()
                Button("취소") { dismiss() }.buttonStyle(.glassCapsule)
                Button(pending ? "시작하는 중…" : "롤백 배포 시작", role: .destructive) {
                    Task {
                        pending = true
                        defer { pending = false }
                        do { try await onConfirm(chosen) } catch { errorMessage = error.localizedDescription }
                    }
                }
                .buttonStyle(.glassCapsule)
                .disabled(pending || chosen.isEmpty || confirm != projectName)
            }
        }
        .padding(24)
        .frame(minWidth: 380)
        .presentationDetents([.medium])
    }
}
