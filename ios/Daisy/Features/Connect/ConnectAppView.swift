import SwiftUI
import UniformTypeIdentifiers

/// W-02 애플리케이션 연결 · W-02b 업로드. 처음 한 번만 해요.
/// 연결하면 L-01 전환 로딩을 보여주다가 첫 배포(이미지 빌드, W-03)가 생기면 그리로 넘어가요.
struct ConnectAppView: View {
    enum Source: Hashable { case github, upload }

    @Environment(AppModel.self) private var app
    @Environment(Router.self) private var router
    @Environment(Workspace.self) private var workspace
    @State private var source: Source = .github
    @State private var repositoryURL = ""
    @State private var branch = "main"
    @State private var inspection: RepositoryInspection?
    @State private var inspecting = false
    @State private var working = false
    @State private var errorMessage: String?
    @State private var connectedProject: Project?
    // 업로드
    @State private var importing = false
    @State private var uploadName: String?
    @State private var uploadProgress: Double?

    var body: some View {
        if let connectedProject {
            ConnectingView(project: connectedProject)
        } else {
            FlowPage(step: 1,
                     title: source == .github ? "애플리케이션 연결" : "애플리케이션 연결 · 업로드",
                     description: source == .github
                        ? "배포할 저장소를 연결해요. 처음 한 번만 하면 돼요."
                        : "GitHub 없이 폴더나 zip을 올려 연결하는 경우예요.") {
                sourceCards
                if source == .github { githubForm } else { uploadForm }
                if let errorMessage { InlineAlert(.danger, "연결하지 못했어요", errorMessage) }
                FlowButtons {
                    Button("취소") { router.popToRoot() }
                        .buttonStyle(.glassCapsule)
                    if source == .github {
                        Button { Task { await connect() } } label: {
                            if working { ProgressView().controlSize(.small) } else { Text("연결하기") }
                        }
                        .buttonStyle(.glassProminent)
                        .disabled(working || repositoryURL.isEmpty || app.isViewer)
                    } else {
                        Button { importing = true } label: {
                            if working { ProgressView().controlSize(.small) } else { Text("업로드하고 연결") }
                        }
                        .buttonStyle(.glassProminent)
                        .disabled(working || app.isViewer)
                    }
                }
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.zip, .folder]) { result in
                if case .success(let url) = result { Task { await upload(url) } }
            }
        }
    }

    // MARK: 입력 방식 카드

    private var sourceCards: some View {
        AdaptiveGrid(minimumWidth: 240) {
            sourceCard(.github, symbol: "arrow.triangle.merge", title: "GitHub 레포 연결",
                       detail: "main에 merge하면 GitHub Actions가 이미지를 빌드해요")
            sourceCard(.upload, symbol: "square.and.arrow.up", title: "소스 업로드",
                       detail: "폴더나 zip을 올려서 연결해요")
        }
    }

    private func sourceCard(_ value: Source, symbol: String, title: String, detail: String) -> some View {
        let isOn = source == value
        return Button { withAnimation(.snappy) { source = value } } label: {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: symbol).font(.title3)
                Text(title).font(.headline)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardStyle()
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(isOn ? AnyShapeStyle(.tint) : AnyShapeStyle(.clear), lineWidth: 2))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    // MARK: GitHub

    private var githubForm: some View {
        AdaptiveGrid(minimumWidth: 320) {
            SectionCard("저장소") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("저장소 URL").font(.subheadline.weight(.medium))
                    TextField("https://github.com/owner/repo", text: $repositoryURL)
                        .urlInput()
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { Task { await inspect() } }
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("배포 기준 브랜치").font(.subheadline.weight(.medium))
                    Menu {
                        ForEach(inspection?.branches ?? [branch], id: \.self) { name in
                            Button(name) { branch = name; Task { await inspect() } }
                        }
                    } label: {
                        Label(branch, systemImage: "arrow.triangle.branch")
                    }
                    .menuStyle(.button)
                    .buttonStyle(.glassCapsule)
                    .fixedSize()
                }
                InlineAlert(.info, "안내", "main에 merge할 때마다 이미지가 커밋 해시 태그로 만들어져요.")
            }
            SectionCard("배포 명세 확인") {
                if inspecting {
                    ProgressView()
                } else if let inspection {
                    HStack(spacing: 12) {
                        detected("Dockerfile", inspection.dockerfile)
                        detected("deploy.yaml", inspection.deployYaml)
                    }
                    InfoRow("포트", inspection.port.map(String.init))
                    InfoRow("헬스체크 경로", inspection.healthcheck, monospaced: true)
                    InfoRow("환경변수", envSummary(inspection.env))
                    InfoRow("DB 필요", inspection.database.map { $0 ? "예" : "아니요 (상태 없는 앱)" })
                } else {
                    Text("저장소 URL을 넣으면 Dockerfile과 deploy.yaml을 확인해요.").foregroundStyle(.secondary)
                }
            }
        }
        .task(id: repositoryURL) {
            // 입력이 멈추면 확인해요
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled, repositoryURL.hasPrefix("https://") else { return }
            await inspect()
        }
    }

    private func detected(_ file: String, _ ok: Bool) -> some View {
        Label(file, systemImage: ok ? "checkmark.circle.fill" : "xmark.circle")
            .font(.caption.monospaced())
            .foregroundStyle(ok ? .green : .red)
    }

    /// 웹: "LOG_LEVEL 외 1개"
    private func envSummary(_ env: [String]) -> String {
        guard let first = env.first else { return "없음" }
        return env.count > 1 ? "\(first) 외 \(env.count - 1)개" : first
    }

    // MARK: 업로드

    private var uploadForm: some View {
        SectionCard("소스 업로드") {
            Button { importing = true } label: {
                VStack(spacing: 8) {
                    Image(systemName: "square.and.arrow.up").font(.largeTitle)
                    Text("폴더나 zip 파일을 끌어다 놓으세요").font(.subheadline.weight(.medium))
                    Text(".gitignore · node_modules는 자동으로 제외돼요").font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 160)
                .background(.fill.quaternary, in: .rect(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [6])).foregroundStyle(.separator))
            }
            .buttonStyle(.plain)
            .dropDestination(for: URL.self) { urls, _ in
                guard let url = urls.first else { return false }
                Task { await upload(url) }
                return true
            }
            if let uploadProgress {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("업로드 중").font(.caption)
                        Spacer()
                        Text("\(Int(uploadProgress * 100))%").font(.caption.monospacedDigit())
                    }
                    ProgressView(value: uploadProgress)
                    if let uploadName { Text(uploadName).font(.caption).foregroundStyle(.secondary) }
                }
            }
        }
    }

    // MARK: 동작

    private func inspect() async {
        guard let client = app.client, !repositoryURL.isEmpty else { return }
        inspecting = true
        defer { inspecting = false }
        inspection = try? await client.send(.inspectRepository(url: repositoryURL, branch: branch))
    }

    private func connect() async {
        guard let client = app.client else { return }
        working = true
        defer { working = false }
        do {
            let project = try await client.send(.connectProject(repositoryURL: repositoryURL, branch: branch))
            app.selectedProjectID = project.id
            connectedProject = project
            await workspace.refresh(using: app)
        } catch {
            app.handle(error)
            errorMessage = error.localizedDescription
        }
    }

    private func upload(_ url: URL) async {
        guard let client = app.client else { return }
        working = true
        defer { working = false }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        uploadName = url.lastPathComponent
        uploadProgress = 0
        do {
            let project = try await client.send(.createUploadProject(name: url.deletingPathExtension().lastPathComponent))
            let ticket = try await client.send(.uploadTicket(projectID: project.id))
            try await client.upload(fileAt: url, to: ticket.url) { value in
                Task { @MainActor in uploadProgress = value }
            }
            _ = try await client.send(.registerSource(projectID: project.id, storageKey: ticket.storageKey))
            app.selectedProjectID = project.id
            connectedProject = project
            await workspace.refresh(using: app)
        } catch {
            app.handle(error)
            errorMessage = error.localizedDescription
            uploadProgress = nil
        }
    }
}

/// L-01 전환 로딩: 새 프로젝트의 첫 배포(이미지 빌드)가 생기면 그 화면으로 넘어가요.
private struct ConnectingView: View {
    let project: Project
    @Environment(AppModel.self) private var app
    @Environment(Router.self) private var router

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            FlowStepper(current: 1).padding(20)
            TransitionLoader(stage: .repository)
        }
        .navigationTitle("애플리케이션 연결")
        .task {
            await poll {
                guard let client = app.client,
                      let first = try? await client.send(.deployments(projectID: project.id)).items.first else { return }
                router.replaceTop(with: .run(first.id))
            }
        }
    }
}
