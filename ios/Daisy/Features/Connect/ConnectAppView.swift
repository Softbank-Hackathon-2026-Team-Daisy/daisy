import SwiftUI

/// W-02 애플리케이션 연결 (WR-02 · WR-03). 처음 한 번만 해요. 입력은 GitHub 저장소 하나예요 (ADR-004, W-02b 업로드는 9/30 범위 제외).
/// 연결하면 deploy.yaml 검증 결과를 보여주고, 문제가 없으면 L-01 전환 로딩 → 첫 빌드(W-03)로 넘어가요.
struct ConnectAppView: View {
    /// 웹과 같은 형식 검사: https://github.com/소유자/저장소
    static let githubURL = /^https:\/\/github\.com\/[\w.\-]+\/[\w.\-]+\/?$/
    /// 브랜치 목록 API가 없어서 흔한 이름만 골라요 (웹과 같아요, 가칭)
    static let branches = ["main", "develop"]

    @Environment(AppModel.self) private var app
    @Environment(Router.self) private var router
    @Environment(Workspace.self) private var workspace
    @State private var repositoryURL = ""
    @State private var branch = "main"
    @State private var working = false
    @State private var errorMessage: String?
    @State private var project: Project?
    @State private var manifest: Manifest?
    @State private var proceeding = false

    private var trimmedURL: String { repositoryURL.trimmingCharacters(in: .whitespaces) }
    private var isValidURL: Bool { trimmedURL.wholeMatch(of: Self.githubURL) != nil }

    var body: some View {
        if proceeding, let project {
            ConnectingView(project: project)
        } else {
            FlowPage(step: 1, title: "애플리케이션 연결", description: "배포할 저장소를 연결해요. 처음 한 번만 하면 돼요.") {
                sourceCard
                githubForm
                if let errorMessage { InlineAlert(.danger, "연결하지 못했어요", errorMessage) }
                FlowButtons {
                    Button("취소") { router.popToRoot() }
                        .buttonStyle(.glassCapsule)
                    // deploy.yaml 오류를 고친 뒤 다시 누르면 명세를 다시 읽어요
                    Button(working ? "연결하는 중…" : "연결하기") {
                        Task { project == nil ? await connect() : await loadManifest() }
                    }
                    .buttonStyle(.glassProminent)
                    .disabled(working || !isValidURL || app.isViewer)
                }
            }
        }
    }

    // MARK: 입력 방식 카드 (GitHub 하나)

    private var sourceCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "arrow.triangle.merge").font(.title3)
            Text("GitHub 레포 연결").font(.headline)
            Text("main에 merge하면 Jenkins가 이미지를 빌드해요").font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.tint, lineWidth: 2))
        .accessibilityAddTraits(.isSelected)
    }

    // MARK: GitHub

    private var githubForm: some View {
        AdaptiveGrid(minimumWidth: 320) {
            SectionCard("저장소") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("저장소 URL").font(.subheadline.weight(.medium))
                    TextField("https://github.com/team/app", text: $repositoryURL)
                        .urlInput()
                        .textFieldStyle(.roundedBorder)
                        .disabled(project != nil)
                    if !repositoryURL.isEmpty && !isValidURL {
                        Text("https://github.com/소유자/저장소 형식으로 적어 주세요").font(.caption).foregroundStyle(.red)
                    }
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("배포 기준 브랜치").font(.subheadline.weight(.medium))
                    Picker("배포 기준 브랜치", selection: $branch) {
                        ForEach(Self.branches, id: \.self) { Text($0) }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .fixedSize()
                    .disabled(project != nil)
                }
                InlineAlert(.info, "안내", "\(branch)에 merge할 때마다 이미지가 커밋 해시 태그로 만들어져요.")
            }
            SectionCard("배포 명세 확인") {
                if working && manifest == nil {
                    ProgressView()
                } else if let manifest {
                    HStack(spacing: 8) {
                        detected("Dockerfile", found: true)
                        detected("deploy.yaml", found: (manifest.errors ?? []).isEmpty)
                    }
                    ManifestRows(manifest: manifest)
                } else {
                    ContentUnavailableView("연결하면 배포 명세를 읽어요", systemImage: "magnifyingglass",
                                           description: Text("저장소의 Dockerfile과 deploy.yaml(포트 · 헬스체크 · 환경변수 · DB)을 확인해요"))
                }
            }
        }
    }

    /// 웹 Detected Chip: "✓ Dockerfile"
    private func detected(_ name: String, found: Bool) -> some View {
        Label(name, systemImage: found ? "checkmark.circle.fill" : "xmark.circle.fill")
            .font(.caption.monospaced())
            .foregroundStyle(found ? .green : .red)
    }

    // MARK: 동작

    private func connect() async {
        guard let client = app.client else { return }
        working = true
        defer { working = false }
        do {
            let created = try await client.send(.connectProject(repository: trimmedURL, branch: branch))
            app.selectedProjectID = created.id
            project = created
            errorMessage = nil
            await workspace.refresh(using: app)
        } catch {
            app.handle(error)
            errorMessage = error.localizedDescription
            return
        }
        await fetchManifest()
    }

    private func loadManifest() async {
        working = true
        defer { working = false }
        await fetchManifest()
    }

    private func fetchManifest() async {
        guard let client = app.client, let project else { return }
        do {
            manifest = try await client.send(.manifest(projectID: project.id))
            if (manifest?.errors ?? []).isEmpty { proceeding = true }
        } catch {
            app.handle(error)
            errorMessage = error.localizedDescription
        }
    }
}

/// L-01 전환 로딩: 새 프로젝트의 첫 빌드(A-06)가 들어오면 W-03으로 넘어가요.
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
                      let first = try? await client.send(.builds(projectID: project.id)).items.first else { return }
                router.replaceTop(with: .build(commit: first.commit))
            }
        }
    }
}
