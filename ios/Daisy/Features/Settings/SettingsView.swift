import SwiftUI

/// W-13 설정: 맨 위에 계정(로그인 정보 · 로그아웃), 이 프로젝트의 저장소 연결(프로젝트 상세), 배포 명세(WR-03), 비밀값, 알림.
/// 맨 아래에 앱 설정(언어 · 서버 · 버전).
struct SettingsView: View {
    @Environment(AppModel.self) private var app
    @Environment(Router.self) private var router
    @Environment(Workspace.self) private var workspace
    @Environment(LanguageStore.self) private var language
    /// 프로젝트 상세 · 배포 명세. 프로젝트에 묶여서 바뀌면 이전 값을 버려요 (10/3 신선도 검수 ST2)
    @State private var details = ScopedLoader<ProjectDetail>()
    @State private var manifests = ScopedLoader<Manifest>()
    @State private var disconnecting = false
    @State private var toast: ToastMessage?
    // 앱이 켜져 있을 때 뜨는 푸시 배너만 걸러요 (PushPayload.presentsInForeground). 앱이 꺼져 있을 때 오는 푸시는 운영체제가 보여줘서 앱이 거를 수 없어요
    @AppStorage(PushPayload.SettingKey.approval) private var notifyApproval = true
    @AppStorage(PushPayload.SettingKey.finished) private var notifyFinished = true
    @AppStorage(PushPayload.SettingKey.failed) private var notifyFailed = true
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        PageScaffold(.app("설정"), subtitle: .app("이 프로젝트의 저장소 연결, 배포 명세, 비밀값, 알림을 관리해요.")) {
            EmptyView()
        } content: {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    StaleBanner(since: staleSince)
                    accountCard
                    if app.selectedProjectID != nil {
                        projectSettings
                    }
                    appSettings
                }
                .padding(20)
            }
        }
        // 웹훅 마지막 수신 · 명세가 처음 값에 고정되지 않게 (ST1): 프로젝트 이벤트(앱 복귀 · 전환 포함)가 오면 바로, 아니면 SSE 15초 · 5초
        .task(id: app.selectedProjectID) {
            await poll(on: workspace.live.changes, every: { PollInterval.seconds(live: workspace.live.isLive) }) { await load() }
        }
        // 기기 설정에서 알림을 켜고 돌아오면 바로 "허용됨"으로 바뀌어요
        .task { await app.push.refreshAuthorization() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await app.push.refreshAuthorization() } }
        }
        .toast($toast)
        .sheet(isPresented: $disconnecting) {
            DisconnectDialog(name: workspace.project?.name ?? "") { try await disconnect() }
        }
    }

    // MARK: 프로젝트 설정 (웹 W-13)

    private var detail: ProjectDetail? { details.value(for: app.selectedProjectID) }
    private var manifest: Manifest? { manifests.value(for: app.selectedProjectID) }

    /// 상세 · 명세 중 하나라도 갱신에 실패했으면 더 오래된 마지막 수신 시각
    private var staleSince: Date? {
        guard app.selectedProjectID != nil else { return nil }
        return [details.staleSince, manifests.staleSince].compactMap { $0 }.min()
    }

    @ViewBuilder
    private var projectSettings: some View {
        AdaptiveGrid(minimumWidth: 320) {
            SectionCard(.app("저장소")) {
                InfoRow("GitHub", detail?.repository ?? workspace.project?.repository)
                InfoRow(.app("기준 브랜치"), detail?.branch ?? workspace.project?.branch, monospaced: true)
                InfoRow(.app("빌드"), detail?.build)
                // 레지스트리는 팀이 아직 정하지 않았어요 (Docker Hub / GHCR)
                InfoRow(.app("레지스트리"), .app("\(detail?.registry ?? "—") [미정]"))
                InfoRow(String.app("웹훅"), detail?.webhookLastAt.map { String.app("수신 중 · 마지막 \(TimeText.clock($0))") })
                Button("저장소 다시 연결") { router.open(.connectProject) }
                    .buttonStyle(.glassCapsule)
                    .disabled(app.isViewer)
            }
            SectionCard(.app("배포 명세 (deploy.yaml)")) {
                Text("저장소의 deploy.yaml이 기준이에요. 여기서는 읽기만 해요.").font(.subheadline).foregroundStyle(.secondary)
                if let manifest {
                    // 웹: 원문 코드 블록 (원문이 없으면 포트 · 헬스체크)
                    CodeBlock(header: manifest.ref ?? "deploy.yaml",
                              code: manifest.raw ?? "port: \(manifest.port.map(String.init) ?? "")\nhealthcheck: \(manifest.healthcheck ?? "")")
                    ForEach(manifest.errors ?? [], id: \.self) { problem in
                        InlineAlert(.danger, .app("deploy.yaml을 확인해 주세요"), [problem.path, problem.message].compactMap { $0 }.joined(separator: ": "))
                    }
                } else if case .failed = manifests.state(for: app.selectedProjectID) {
                    Text("deploy.yaml을 불러오지 못했어요").foregroundStyle(.secondary)
                } else {
                    ProgressView().frame(maxWidth: .infinity)
                }
            }
            SectionCard(.app("비밀값")) {
                Text("deploy.yaml의 secrets에 적힌 이름만 값을 넣어요. 값은 다시 볼 수 없어요.")
                    .font(.subheadline).foregroundStyle(.secondary)
                if let secrets = manifest?.secrets, !secrets.isEmpty {
                    ForEach(secrets, id: \.self) { name in
                        InfoRow(name, .app("●●●● (전달 방식 [미정])"), monospaced: true)
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
                    .emptyStateCentered()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
            }
            SectionCard(.app("알림")) {
                // 기기(운영체제) 알림 권한. 꺼져 있으면 푸시가 와도 보이지 않아요 (원격 알림은 지금 iPhone만)
                if app.push.supportsRemote {
                    InfoRow(.app("기기 알림"), pushAuthorizationText)
                    if app.push.authorization == .denied, let url = PushRegistry.systemSettingsURL {
                        Button("알림 설정 열기", systemImage: "bell.badge") { openURL(url) }
                            .buttonStyle(.glassCapsule)
                    }
                }
                Toggle("승인이 필요할 때 · Swift 앱 푸시", isOn: $notifyApproval)
                Toggle("배포가 끝났을 때", isOn: $notifyFinished)
                Toggle("배포가 실패했을 때", isOn: $notifyFailed)
                Text("브라우저 알림은 웹에서 켜요.").font(.caption).foregroundStyle(.secondary)
            }
        }
        SectionCard(.app("프로젝트 연결 해제")) {
            Text("배포 서비스에서 이 프로젝트를 지워요. 이미 떠 있는 인프라는 지워지지 않아요 (terraform destroy는 따로 해요).")
                .font(.subheadline).foregroundStyle(.secondary)
            Button("연결 해제", role: .destructive) { disconnecting = true }
                .buttonStyle(.glassCapsule)
                .disabled(app.isViewer)
        }
    }

    /// 허용됨 · 꺼짐 (기기 설정에서 켜도록 안내) · 아직 묻지 않음
    private var pushAuthorizationText: String? {
        switch app.push.authorization {
        case .allowed: .app("허용됨")
        case .denied: .app("꺼짐 · 설정에서 알림을 켜 주세요")
        case .notDetermined: .app("아직 묻지 않았어요")
        case .unknown: nil
        }
    }

    // MARK: 계정 (10/3: 설정 맨 위, 모든 화면에서 로그아웃. Mac 사이드바 계정 줄의 로그아웃도 그대로 있어요)

    private var accountCard: some View {
        SectionCard(.app("계정")) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    accountIdentity
                    Spacer(minLength: 12)
                    signOutButton
                }
                VStack(alignment: .leading, spacing: 12) {
                    accountIdentity
                    signOutButton
                }
            }
        }
    }

    private var accountIdentity: some View {
        HStack(spacing: 12) {
            Avatar(name: app.displayName)
            VStack(alignment: .leading, spacing: 2) {
                Text(app.displayName ?? String.app("로그인됨")).font(.headline).lineLimit(1)
                Text(app.isViewer ? String.app("읽기 전용") : String.app("팀 계정 · 승인 가능"))
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var signOutButton: some View {
        Button("로그아웃", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) { app.signOut() }
            .buttonStyle(.glassCapsule)
    }

    // MARK: 앱 설정 (앱에만 있어요)

    private var appSettings: some View {
        @Bindable var app = app
        return SectionCard(.app("앱")) {
            languagePicker
            // 서버는 Unibloom 고정이라 바꾸는 칸 없이 보여만 줘요
            InfoRow(.app("서버"), app.serverURL?.host() ?? "—", monospaced: true)
            InfoRow(.app("버전"), Bundle.main.versionText)
        }
    }

    /// 언어 (10/2): 기기 설정 따르기 · 한국어 · English · 日本語. 고르면 바로 바뀌어요 (다시 켜지 않아도 돼요).
    /// 한 줄에 다 들어가면 세그먼트, 좁은 화면(iPhone)은 같은 글래스 캡슐 메뉴로 보여줘요.
    private var languagePicker: some View {
        @Bindable var language = language
        let items = LanguageSetting.allCases.map { GlassSegmented.Item(value: $0, title: $0.title) }
        return VStack(alignment: .leading, spacing: 6) {
            Text("언어").font(.subheadline.weight(.medium))
            ViewThatFits(in: .horizontal) {
                GlassSegmented(selection: $language.setting, items: items)
                Menu {
                    Picker("언어", selection: $language.setting) {
                        ForEach(LanguageSetting.allCases) { Text(verbatim: $0.title).tag($0) }
                    }
                    .pickerStyle(.inline)
                } label: {
                    Label { Text(verbatim: language.setting.title) } icon: { Image(systemName: "globe") }
                }
                .menuStyle(.button)
                .menuIndicator(.hidden)
                .buttonStyle(.glassCapsule)
                .fixedSize()
            }
            Text("앱 화면 글자가 바뀌어요. 서버가 보낸 메시지(오류 · 로그 · plan 위험 설명 등)는 받은 그대로 보여요.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    // MARK: 동작

    /// 상세와 명세를 함께 받아요. 실패는 `try?`로 삼키지 않고 `app.handle`로 넘겨요 (401이면 로그아웃, X2)
    private func load() async {
        guard let client = app.client, let projectID = app.selectedProjectID else { return }
        await details.load(projectID, using: app) {
            try await client.send(.projectDetail(projectID: projectID))
        }
        await manifests.load(projectID, using: app) {
            try await client.send(.manifest(projectID: projectID))
        }
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
        } catch let error as APIError where error.isStateConflict {
            // 서버 409는 일반 문구라, 이유를 알 수 있게 바꿔 보여줘요 (#59 · 웹 #64 리뷰)
            throw APIError.server(status: 409, code: "PROJECT_BUSY",
                                  message: .app("진행 중인 배포(대기 · 승인 대기 포함)가 있어 해제할 수 없어요"), retryable: false)
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
            if let errorMessage { InlineAlert(.danger, .app("연결을 해제하지 못했어요"), errorMessage) }
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
        InfoRow(.app("포트"), manifest.port.map(String.init))
        InfoRow(.app("헬스체크 경로"), manifest.healthcheck, monospaced: true)
        InfoRow(.app("환경변수"), Self.summary(manifest.env ?? []))
        InfoRow(String.app("DB 필요"), manifest.database.map { $0 ? String.app("예") : String.app("아니요 (상태 없는 앱)") })
        ForEach(manifest.errors ?? [], id: \.self) { problem in
            InlineAlert(.danger, .app("deploy.yaml을 확인해 주세요"), [problem.path, problem.message].compactMap { $0 }.joined(separator: ": "))
        }
    }

    /// 웹: "LOG_LEVEL 외 1개"
    static func summary(_ env: [String]) -> String {
        guard let first = env.first else { return .app("없음") }
        return env.count > 1 ? String.app("\(first) 외 \(env.count - 1)개") : first
    }
}
