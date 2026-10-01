import SwiftUI

/// W-13 설정: 이 프로젝트의 저장소 연결(프로젝트 상세), 배포 명세(WR-03), 비밀값, 알림. 맨 아래에 앱 설정(서버 · 계정 · 버전).
struct SettingsView: View {
    @Environment(AppModel.self) private var app
    @Environment(Router.self) private var router
    @Environment(Workspace.self) private var workspace
    @State private var detail: ProjectDetail?
    @State private var manifest: Manifest?
    @State private var disconnecting = false
    @State private var confirmName = ""
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
        .alert("프로젝트 연결 해제", isPresented: $disconnecting) {
            TextField("프로젝트 이름", text: $confirmName)
            Button("취소", role: .cancel) { confirmName = "" }
            Button("연결 해제", role: .destructive) { Task { await disconnect() } }
        } message: {
            Text("되돌릴 수 없어요. 확인을 위해 프로젝트 이름(\(workspace.project?.name ?? ""))을 입력해 주세요. 이미 떠 있는 인프라는 지워지지 않아요.")
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
                InfoRow("레지스트리", detail?.registry)
                InfoRow("웹훅", detail?.webhookLastAt.map { "수신 중 · 마지막 \($0.formatted(date: .omitted, time: .shortened))" })
                Button("저장소 다시 연결") { router.open(.connectProject) }
                    .buttonStyle(.glassCapsule)
                    .disabled(app.isViewer)
            }
            SectionCard("배포 명세 (deploy.yaml)") {
                Text("저장소의 deploy.yaml이 기준이에요. 여기서는 읽기만 해요.").font(.subheadline).foregroundStyle(.secondary)
                if let manifest {
                    ManifestRows(manifest: manifest)
                    if let raw = manifest.raw {
                        CodeBlock(header: manifest.ref ?? "deploy.yaml", code: raw)
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
                        Label(name, systemImage: "key").font(.subheadline.monospaced())
                    }
                } else {
                    VStack(spacing: 6) {
                        Image(systemName: "key").font(.title2).foregroundStyle(.secondary)
                        Text("이 앱은 비밀값이 없어요").font(.subheadline.weight(.medium))
                        Text("secrets: [] · 전달 방식(GitHub Secrets / 시크릿 매니저 / 서버 암호화 저장)은 [미정]")
                            .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
                // WR-12: 전달 방식이 팀 결정 대기라 아직 열 수 없어요
                Button("비밀값 추가") { }
                    .buttonStyle(.glassCapsule)
                    .disabled(true)
                    .help("비밀값 전달 방식이 정해지면 열려요")
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

    private func disconnect() async {
        guard let client = app.client, let projectID = app.selectedProjectID,
              confirmName.trimmingCharacters(in: .whitespaces) == workspace.project?.name else {
            toast = ToastMessage(kind: .danger, title: "프로젝트 이름이 달라요", message: "연결 해제하지 않았어요.")
            confirmName = ""
            return
        }
        do {
            _ = try await client.send(.disconnectProject(projectID: projectID))
            confirmName = ""
            app.selectedProjectID = nil
            await workspace.refresh(using: app)
            router.tab = .overview
        } catch {
            app.handle(error)
            toast = ToastMessage(kind: .danger, title: "연결 해제하지 못했어요", message: error.localizedDescription)
        }
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
            InlineAlert(.danger, problem.path ?? "deploy.yaml", problem.message)
        }
    }

    /// 웹: "LOG_LEVEL 외 1개"
    static func summary(_ env: [String]) -> String {
        guard let first = env.first else { return "없음" }
        return env.count > 1 ? "\(first) 외 \(env.count - 1)개" : first
    }
}
