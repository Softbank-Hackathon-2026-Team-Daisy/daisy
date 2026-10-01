import SwiftUI

/// W-13 설정: 이 프로젝트의 저장소 연결(프로젝트 상세), 배포 명세(WR-03), 비밀값, 알림. 맨 아래에 앱 설정(서버 · 계정 · 버전).
struct SettingsView: View {
    @Environment(AppModel.self) private var app
    @Environment(Router.self) private var router
    @Environment(Workspace.self) private var workspace
    @State private var detail: ProjectDetail?
    @State private var manifest: Manifest?
    @State private var disconnecting = false
    @State private var toast: ToastMessage?
    @AppStorage("notify.approval") private var notifyApproval = true
    @AppStorage("notify.finished") private var notifyFinished = true
    @AppStorage("notify.failed") private var notifyFailed = true

    var body: some View {
        PageScaffold("설정", subtitle: "이 프로젝트의 저장소 연결, 배포 명세, 비밀값, 알림을 관리해요.") {
            EmptyView()
        } content: {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if app.selectedProjectID != nil {
                        projectSettings
                    }
                    appSettings
                }
                .padding(20)
            }
        }
        .task(id: app.selectedProjectID) { await load() }
        .toast($toast)
        .sheet(isPresented: $disconnecting) {
            DisconnectDialog(name: workspace.project?.name ?? "") { try await disconnect() }
        }
    }

    // MARK: 프로젝트 설정 (웹 W-13)

    @ViewBuilder
    private var projectSettings: some View {
        AdaptiveGrid(minimumWidth: 320) {
            SectionCard("저장소") {
                InfoRow("GitHub", detail?.repository ?? workspace.project?.repository)
                InfoRow("기준 브랜치", detail?.branch ?? workspace.project?.branch, monospaced: true)
                InfoRow("빌드", detail?.build)
                // 레지스트리는 팀이 아직 정하지 않았어요 (Docker Hub / GHCR)
                InfoRow("레지스트리", "\(detail?.registry ?? "—") [미정]")
                InfoRow("웹훅", detail?.webhookLastAt.map { "수신 중 · 마지막 \(TimeText.clock($0))" })
                Button("저장소 다시 연결") { router.open(.connectProject) }
                    .buttonStyle(.glassCapsule)
                    .disabled(app.isViewer)
            }
            SectionCard("배포 명세 (deploy.yaml)") {
                Text("저장소의 deploy.yaml이 기준이에요. 여기서는 읽기만 해요.").font(.subheadline).foregroundStyle(.secondary)
                if let manifest {
                    // 웹: 원문 코드 블록 (원문이 없으면 포트 · 헬스체크)
                    CodeBlock(header: manifest.ref ?? "deploy.yaml",
                              code: manifest.raw ?? "port: \(manifest.port.map(String.init) ?? "")\nhealthcheck: \(manifest.healthcheck ?? "")")
                    ForEach(manifest.errors ?? [], id: \.self) { problem in
                        InlineAlert(.danger, "deploy.yaml을 확인해 주세요", [problem.path, problem.message].compactMap { $0 }.joined(separator: ": "))
                    }
                } else {
                    Text("deploy.yaml을 불러오지 못했어요").foregroundStyle(.secondary)
                }
            }
            SectionCard("비밀값") {
                Text("deploy.yaml의 secrets에 적힌 이름만 값을 넣어요. 값은 다시 볼 수 없어요.")
                    .font(.subheadline).foregroundStyle(.secondary)
                if let secrets = manifest?.secrets, !secrets.isEmpty {
                    ForEach(secrets, id: \.self) { name in
                        InfoRow(name, "●●●● (전달 방식 [미정])", monospaced: true)
                    }
                } else {
                    VStack(spacing: 6) {
                        Image(systemName: "lock").font(.title2).foregroundStyle(.secondary)
                        Text("이 앱은 비밀값이 없어요").font(.subheadline.weight(.medium))
                        Text("secrets: [] · 전달 방식(GitHub Secrets / 시크릿 매니저 / 서버 암호화 저장)은 [미정]")
                            .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        // WR-12: 전달 방식이 팀 결정 대기라 아직 열 수 없어요
                        Button("비밀값 추가") { }
                            .buttonStyle(.glassCapsule)
                            .disabled(true)
                            .help("비밀값 전달 방식이 정해지면 열려요")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
            }
            SectionCard("알림") {
                Toggle("승인이 필요할 때 · Swift 앱 푸시", isOn: $notifyApproval)
                Toggle("배포가 끝났을 때", isOn: $notifyFinished)
                Toggle("배포가 실패했을 때", isOn: $notifyFailed)
                Text("브라우저 알림은 웹에서 켜요.").font(.caption).foregroundStyle(.secondary)
            }
        }
        SectionCard("프로젝트 연결 해제") {
            Text("배포 서비스에서 이 프로젝트를 지워요. 이미 떠 있는 인프라는 지워지지 않아요 (terraform destroy는 따로 해요).")
                .font(.subheadline).foregroundStyle(.secondary)
            Button("연결 해제", role: .destructive) { disconnecting = true }
                .buttonStyle(.glassCapsule)
                .disabled(app.isViewer)
        }
    }

    // MARK: 앱 설정 (앱에만 있어요)

    private var appSettings: some View {
        @Bindable var app = app
        return SectionCard("앱") {
            VStack(alignment: .leading, spacing: 6) {
                Text("서버 주소").font(.subheadline.weight(.medium))
                TextField("https://api.example.com", text: $app.serverURLString)
                    .urlInput()
                    .textFieldStyle(.roundedBorder)
                if !app.serverURLString.isEmpty && app.serverURL == nil {
                    Text("https://로 시작하는 주소를 넣어 주세요.").font(.caption).foregroundStyle(.red)
                }
            }
            InfoRow("계정", app.username)
            InfoRow("권한", app.isViewer ? "읽기 전용" : "승인 가능")
            InfoRow("버전", Bundle.main.versionText)
            Button("로그아웃", role: .destructive) { app.signOut() }
                .buttonStyle(.glassCapsule)
        }
    }

    // MARK: 동작

    private func load() async {
        guard let client = app.client, let projectID = app.selectedProjectID else { return }
        async let detail = try? client.send(.projectDetail(projectID: projectID))
        async let manifest = try? client.send(.manifest(projectID: projectID))
        self.detail = await detail ?? self.detail
        self.manifest = await manifest ?? self.manifest
    }

    /// 연결을 해제하면 저장소 연결(W-02)로 가요 (웹과 같아요)
    private func disconnect() async throws {
        guard let client = app.client, let projectID = app.selectedProjectID else { return }
        do {
            _ = try await client.send(.disconnectProject(projectID: projectID))
            disconnecting = false
            app.selectedProjectID = nil
            await workspace.refresh(using: app)
            router.open(.connectProject, in: .overview)
        } catch {
            app.handle(error)
            throw error
        }
    }
}

/// 웹 Dialog: "sample-monolith 연결을 해제할까요?" + 이름 입력 + 취소 · 연결 해제
private struct DisconnectDialog: View {
    let name: String
    let onConfirm: () async throws -> Void
    @State private var confirm = ""
    @State private var errorMessage: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("\(name) 연결을 해제할까요?", systemImage: "exclamationmark.triangle").font(.headline)
            Text("되돌릴 수 없어요. 떠 있는 인프라는 그대로 남아요. 확인을 위해 프로젝트 이름을 입력해 주세요.")
                .font(.subheadline).foregroundStyle(.secondary)
            TextField(name, text: $confirm)
                .textFieldStyle(.roundedBorder)
                .plainInput()
            if let errorMessage { InlineAlert(.danger, "연결을 해제하지 못했어요", errorMessage) }
            HStack {
                Spacer()
                Button("취소") { dismiss() }.buttonStyle(.glassCapsule)
                Button("연결 해제", role: .destructive) {
                    Task {
                        do { try await onConfirm() } catch { errorMessage = error.localizedDescription }
                    }
                }
                .buttonStyle(.glassCapsule)
                .disabled(confirm != name)
            }
        }
        .padding(24)
        .frame(minWidth: 380)
        .presentationDetents([.medium])
    }
}

extension Bundle {
    var versionText: String {
        let version = infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }
}

/// 파싱된 deploy.yaml 줄 (WR-03). W-02 배포 명세 확인과 W-13에서 같이 써요.
struct ManifestRows: View {
    let manifest: Manifest

    var body: some View {
        InfoRow("포트", manifest.port.map(String.init))
        InfoRow("헬스체크 경로", manifest.healthcheck, monospaced: true)
        InfoRow("환경변수", Self.summary(manifest.env ?? []))
        InfoRow("DB 필요", manifest.database.map { $0 ? "예" : "아니요 (상태 없는 앱)" })
        ForEach(manifest.errors ?? [], id: \.self) { problem in
            InlineAlert(.danger, "deploy.yaml을 확인해 주세요", [problem.path, problem.message].compactMap { $0 }.joined(separator: ": "))
        }
    }

    /// 웹: "LOG_LEVEL 외 1개"
    static func summary(_ env: [String]) -> String {
        guard let first = env.first else { return "없음" }
        return env.count > 1 ? "\(first) 외 \(env.count - 1)개" : first
    }
}
