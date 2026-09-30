import SwiftUI

/// W-09 배포 이력: 버전 · 커밋 · 상태 · 환경 · 배포자 · 시간 · 롤백.
/// 넓으면 표, 좁으면 목록 (도영 님 메모). 롤백(WR-14)은 새 배포 한 건이고 plan 승인을 거쳐요.
struct HistoryView: View {
    @Environment(AppModel.self) private var app
    @Environment(Router.self) private var router
    @Environment(Workspace.self) private var workspace
    @State private var store = DeploymentsStore()
    @State private var rollbackTarget: Deployment?
    @State private var confirmName = ""
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
                                Text("아직 배포한 기록이 없어요").foregroundStyle(.secondary)
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
            RollbackDialog(deployment: deployment, environments: environmentNames(deployment)) {
                Task { await rollback(deployment) }
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
                    deployment.state.badge
                    environmentTags(deployment)
                    HStack(spacing: 6) { Avatar(name: deployment.createdBy); Text(deployment.createdBy ?? "—").font(.subheadline) }
                    timeText(deployment).font(.caption).foregroundStyle(.secondary)
                    rollbackButton(deployment)
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
                        deployment.state.badge
                    }
                    environmentTags(deployment)
                    HStack {
                        Avatar(name: deployment.createdBy)
                        Text(deployment.createdBy ?? "—").font(.caption)
                        timeText(deployment).font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        rollbackButton(deployment)
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

    /// 웹: "10:12 · 12분 전", "어제 18:40", "9/27 21:05"
    private func timeText(_ deployment: Deployment) -> some View {
        Group {
            if let date = deployment.finishedAt ?? deployment.createdAt {
                HStack(spacing: 4) {
                    Text(date, format: .dateTime.hour().minute())
                    Text("·")
                    RelativeTime(date: date)
                }
            } else {
                Text("—")
            }
        }
    }

    private func rollbackButton(_ deployment: Deployment) -> some View {
        Button("롤백") { rollbackTarget = deployment }
            .buttonStyle(.glassCapsule)
            .disabled(app.isViewer || ![.succeeded, .partiallySucceeded].contains(deployment.state))
    }

    private func environmentNames(_ deployment: Deployment) -> [String] {
        (deployment.targets ?? []).map { workspace.name(of: $0.targetId) }
    }

    // MARK: 롤백

    private func rollback(_ deployment: Deployment) async {
        guard let client = app.client else { return }
        do {
            let next = try await client.send(.rollback(deploymentID: deployment.id,
                                                       targetIDs: (deployment.targets ?? []).map(\.targetId),
                                                       reason: "앱에서 \(deployment.version ?? "이전 버전")로 롤백"))
            rollbackTarget = nil
            toast = ToastMessage(kind: .info, title: "롤백 시작", message: "\(deployment.version ?? "이전 버전")로 되돌리는 plan을 만들고 있어요. 승인하면 배포돼요.")
            router.push(.started(next.id))
        } catch {
            app.handle(error)
            rollbackTarget = nil
            toast = ToastMessage(kind: .danger, title: "롤백하지 못했어요", message: error.localizedDescription)
        }
    }
}

/// 웹 Dialog: "v6로 롤백할까요?" + 환경 이름 입력 + 취소 · 롤백
struct RollbackDialog: View {
    let deployment: Deployment
    let environments: [String]
    let onConfirm: () -> Void
    @State private var name = ""
    @Environment(\.dismiss) private var dismiss

    private var version: String { deployment.version ?? String(deployment.commit.prefix(7)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("\(version)로 롤백할까요?", systemImage: "arrow.counterclockwise").font(.headline)
                Spacer()
                Button { dismiss() } label: { Label("닫기", systemImage: "xmark") }
                    .buttonStyle(GlassCircleButtonStyle(diameter: 28))
            }
            Text("\(environments.joined(separator: " · ")) \(environments.count)개 환경이 모두 \(version)(\(deployment.commit.prefix(7)))로 돌아가요. 확인을 위해 환경 이름을 입력해 주세요.")
                .font(.subheadline).foregroundStyle(.secondary)
            TextField("환경 이름", text: $name)
                .textFieldStyle(.roundedBorder)
                .plainInput()
            HStack {
                Spacer()
                Button("취소") { dismiss() }.buttonStyle(.glassCapsule)
                Button("롤백", role: .destructive) { onConfirm() }
                    .buttonStyle(.glassCapsule)
                    .disabled(!environments.contains(name.trimmingCharacters(in: .whitespaces)))
            }
        }
        .padding(24)
        .frame(minWidth: 380)
        .presentationDetents([.medium])
    }
}
