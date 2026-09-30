import SwiftUI

/// W-08 배포 결과: 환경별 결과 카드(QR · URL · 헬스) · 동일성 검증 · 이력 보기 · QR로 공유.
struct ResultStage: View {
    let deployment: Deployment
    @Environment(AppModel.self) private var app
    @Environment(Router.self) private var router
    @Environment(Workspace.self) private var workspace
    @Environment(\.openURL) private var openURL
    @State private var sharing = false
    @State private var toast: ToastMessage?

    private var targets: [Deployment.Target] { deployment.targets ?? [] }

    var body: some View {
        FlowPage(step: 6, title: "배포 결과", description: "모든 환경이 같은 이미지로 떠 있는지 확인해요.") {
            AdaptiveGrid(minimumWidth: 280) {
                ForEach(targets) { card($0) }
            }
            // 동일성 검증은 A-02의 image_digest로 앱이 만들어요 (WR-09)
            if !workspace.statuses.isEmpty {
                let parity = Parity(statuses: workspace.statuses)
                ParityTable(parity: parity, targets: parity.targets.map { workspace.type(of: $0) })
            }
            FlowButtons {
                Button("이력 보기") { router.tab = .history }
                    .buttonStyle(.glassCapsule)
                Button("QR로 공유") { sharing = true }
                    .buttonStyle(.glassCapsule)
                    .disabled(targets.allSatisfy { $0.url == nil })
            }
        }
        .toast($toast)
        .sheet(isPresented: $sharing) { QRShareSheet(targets: targets) }
    }

    private func card(_ target: Deployment.Target) -> some View {
        let ok = !target.isFailed && target.state != .cancelled
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                EnvTag(type: workspace.type(of: target.targetId))
                Spacer()
                ok ? StatusBadge(text: "성공", color: .green) : StatusBadge(text: "실패", color: .red)
            }
            HStack(alignment: .top, spacing: 12) {
                if let url = target.url {
                    QRCodeImage(text: url.absoluteString).frame(width: 72, height: 72)
                }
                VStack(alignment: .leading, spacing: 4) {
                    if let url = target.url {
                        Text(url.absoluteString).font(.caption.monospaced()).lineLimit(2).textSelection(.enabled)
                    }
                    if ok {
                        Text(target.healthSummary ?? "헬스체크 결과를 기다리고 있어요").font(.caption).foregroundStyle(.secondary)
                    } else {
                        Button("헬스체크 실패 · 원인 보기") {
                            router.push(.logs(deploymentID: deployment.id, targetID: target.targetId))
                        }
                        .buttonStyle(.plain)
                        .font(.caption)
                        .foregroundStyle(.red)
                    }
                }
            }
            HStack(spacing: 8) {
                if ok {
                    Button("열기") { if let url = target.url { openURL(url) } }
                        .buttonStyle(.glassCapsule)
                        .disabled(target.url == nil)
                } else {
                    Button("다시 시도") { Task { await retry(target) } }
                        .buttonStyle(.glassCapsule)
                        .disabled(app.isViewer)
                }
                Button("URL 복사") {
                    if let url = target.url {
                        Clipboard.copy(url.absoluteString)
                        toast = ToastMessage(kind: .success, title: "URL을 복사했어요")
                    }
                }
                .buttonStyle(.glassCapsule)
                .disabled(target.url == nil)
            }
        }
        .cardStyle()
    }

    /// 실패한 환경만 같은 커밋으로 새 배포를 만들어요 (WR-05)
    private func retry(_ target: Deployment.Target) async {
        guard let client = app.client else { return }
        do {
            let next = try await client.send(.startDeployment(projectID: deployment.projectId, commit: deployment.commit,
                                                              targetIDs: [target.targetId]))
            router.push(.started(next.id))
        } catch {
            app.handle(error)
            toast = ToastMessage(kind: .danger, title: "다시 시도하지 못했어요", message: error.localizedDescription)
        }
    }
}

/// "QR로 공유": 환경별 QR을 크게 보여주고 URL을 공유해요 (TestFlight 링크 QR도 여기 둘 수 있어요).
private struct QRShareSheet: View {
    let targets: [Deployment.Target]
    @Environment(Workspace.self) private var workspace
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                AdaptiveGrid(minimumWidth: 220) {
                    ForEach(targets.filter { $0.url != nil }) { target in
                        VStack(spacing: 10) {
                            EnvTag(type: workspace.type(of: target.targetId))
                            QRCodeImage(text: target.url!.absoluteString).frame(width: 180, height: 180)
                            ShareLink(item: target.url!) { Label("공유", systemImage: "square.and.arrow.up") }
                                .buttonStyle(.glassCapsule)
                        }
                        .cardStyle()
                    }
                }
                .padding(20)
            }
            .navigationTitle("QR로 공유")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("닫기") { dismiss() }
                }
            }
        }
        .frame(minWidth: 480, minHeight: 420)
    }
}
