import SwiftUI

/// W-08 배포 결과: 환경별 결과 카드(QR · URL · 헬스) · 동일성 검증 · 이력 보기 · QR로 공유.
struct ResultStage: View {
    let deployment: Deployment
    @Environment(AppModel.self) private var app
    @Environment(Router.self) private var router
    @Environment(Workspace.self) private var workspace
    @Environment(\.openURL) private var openURL
    @Environment(\.adoptDeployment) private var adoptDeployment
    @State private var retrying = false
    @State private var sharing = false
    @State private var toast: ToastMessage?

    private var targets: [Deployment.Target] { deployment.targets ?? [] }

    var body: some View {
        FlowPage(step: 6, title: .app("배포 결과"), description: FlowCopy.result(deployment, name: workspace.name(of:))) {
            HStack { deployment.badge; Spacer() }
            AdaptiveGrid(minimumWidth: 280) {
                ForEach(targets) { card($0) }
            }
            // 동일성 검증은 이 배포의 환경별 결과(A-04 `image_digest` · 헬스)로 앱이 만들어요. 성공한 환경끼리 비교해요 (웹과 같아요)
            if !targets.isEmpty {
                let parity = Parity(deployment: deployment)
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
        let failed = target.isFailed
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                EnvTag(type: workspace.type(of: target.targetId))
                Spacer()
                // 웹: 환경별 상태 그대로 (성공 · 실패 · 취소됨 …)
                target.state?.badge ?? (failed ? StatusBadge(text: .app("실패"), color: .red) : StatusBadge(text: .app("성공"), color: .green))
            }
            HStack(alignment: .top, spacing: 12) {
                if let url = target.url {
                    QRCodeImage(text: url.absoluteString).frame(width: 72, height: 72)
                }
                VStack(alignment: .leading, spacing: 4) {
                    if let url = target.url {
                        Text(url.absoluteString).font(.caption.monospaced()).lineLimit(2).textSelection(.enabled)
                    }
                    if !failed {
                        Text(target.healthSummary ?? "—").font(.caption).foregroundStyle(.secondary)
                    } else {
                        Button(target.step == .healthCheck ? "헬스체크 실패 · 원인 보기" : "apply 실패 · 원인 보기") {
                            router.push(.logs(deploymentID: deployment.id, targetID: target.targetId))
                        }
                        .buttonStyle(.plain)
                        .font(.caption)
                        .foregroundStyle(.red)
                    }
                }
            }
            HStack(spacing: 8) {
                if !failed {
                    Button("열기") { if let url = target.url { openURL(url) } }
                        .buttonStyle(.glassCapsule)
                        .disabled(target.url == nil)
                } else {
                    Button("다시 시도") { Task { await retry(target) } }
                        .buttonStyle(.glassCapsule)
                        .disabled(app.isViewer || retrying)
                }
                Button("URL 복사") {
                    if let url = target.url {
                        Clipboard.copy(url.absoluteString)
                        toast = ToastMessage(kind: .success, title: .app("URL을 복사했어요"))
                    }
                }
                .buttonStyle(.glassCapsule)
                .disabled(target.url == nil)
            }
        }
        .cardStyle()
    }

    /// 실패한 환경만 원본 배포에서 다시 시도해요 (`POST /deployments/{id}/retry`)
    private func retry(_ target: Deployment.Target) async {
        guard let client = app.client, !retrying else { return }
        // 요청을 기다리는 동안 탭을 옮겨도 이 탭에서 열어요 (D13)
        let tab = router.tab
        retrying = true
        defer { retrying = false }
        do {
            let next = try await client.send(.retry(.only(target.targetId, of: deployment)))
            // 같은 배포 화면을 위에 쌓지 않아요: 배포 탭 루트면 루트가 새 배포로 바뀌고, 아니면 이 화면을 바꿔 끼워요 (D12)
            if let adoptDeployment { adoptDeployment(next.id) } else { router.openRetry(next.id, source: deployment.id, in: tab) }
        } catch {
            app.handle(error)
            toast = ToastMessage(kind: .danger, title: .app("다시 시도하지 못했어요"), message: error.localizedDescription)
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
