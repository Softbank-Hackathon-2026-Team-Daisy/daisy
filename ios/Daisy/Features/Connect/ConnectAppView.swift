import SwiftUI

/// W-02 애플리케이션 연결 (WR-02 · WR-03). 처음 한 번만 해요.
/// 연결하면 deploy.yaml 검증 결과를 보여주고, 문제가 없으면 L-01 전환 로딩 → 첫 빌드(W-03)로 넘어가요.
/// W-02b 업로드는 서버가 사용자 코드를 빌드하지 않기로 해서(ADR, 9/30 서버 답변) 설계만 보여줘요.
struct ConnectAppView: View {
    enum Source: Hashable { case github, upload }

    @Environment(AppModel.self) private var app
    @Environment(Router.self) private var router
    @Environment(Workspace.self) private var workspace
    @State private var source: Source = .github
    @State private var repositoryURL = ""
    @State private var branch = "main"
    @State private var working = false
    @State private var errorMessage: String?
    @State private var project: Project?
    @State private var manifest: Manifest?
    @State private var proceeding = false

    var body: some View {
        if proceeding, let project {
            ConnectingView(project: project)
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
                        if project == nil {
                            Button { Task { await connect() } } label: {
                                if working { ProgressView().controlSize(.small) } else { Text("연결하기") }
                            }
                            .buttonStyle(.glassProminent)
                            .disabled(working || repositoryURL.isEmpty || branch.isEmpty || app.isViewer)
                        } else {
                            Button("다시 확인") { Task { await loadManifest() } }
                                .buttonStyle(.glassCapsule)
                                .disabled(working)
                            Button("다음") { proceeding = true }
                                .buttonStyle(.glassProminent)
                                .disabled(working || !(manifest?.errors ?? []).isEmpty)
                        }
                    } else {
                        Button("업로드하고 연결") { }
                            .buttonStyle(.glassProminent)
                            .disabled(true)
                    }
                }
            }
        }
    }

    // MARK: 입력 방식 카드

    private var sourceCards: some View {
        AdaptiveGrid(minimumWidth: 240) {
            sourceCard(.github, symbol: "arrow.triangle.merge", title: "GitHub 레포 연결",
                       detail: "main에 merge하면 GitHub Actions가 이미지를 빌드해요")
            sourceCard(.upload, symbol: "square.and.arrow.up", title: "소스 업로드",
                       detail: "폴더나 zip을 올려서 연결해요 · 설계만")
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
                        .disabled(project != nil)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("배포 기준 브랜치").font(.subheadline.weight(.medium))
                    TextField("main", text: $branch)
                        .plainInput()
                        .textFieldStyle(.roundedBorder)
                        .disabled(project != nil)
                }
                InlineAlert(.info, "안내", "main에 merge할 때마다 이미지가 커밋 해시 태그로 만들어져요.")
            }
            SectionCard("배포 명세 확인") {
                if working {
                    ProgressView()
                } else if let manifest {
                    if (manifest.errors ?? []).isEmpty {
                        Label("deploy.yaml 확인 완료", systemImage: "checkmark.circle.fill")
                            .font(.caption.monospaced()).foregroundStyle(.green)
                    }
                    ManifestRows(manifest: manifest)
                } else {
                    Text("연결하면 Dockerfile과 deploy.yaml을 확인해요.").foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: 업로드 (설계만)

    private var uploadForm: some View {
        SectionCard("소스 업로드") {
            InlineAlert(.info, "설계만 있어요",
                        "업로드 경로는 우리 서비스가 사용자 코드를 직접 빌드해야 해서 예선 범위에서 뺐어요. 지금은 GitHub 연결을 써 주세요.")
            VStack(spacing: 8) {
                Image(systemName: "square.and.arrow.up").font(.largeTitle)
                Text("폴더나 zip 파일을 끌어다 놓으세요").font(.subheadline.weight(.medium))
                Text(".gitignore · node_modules는 자동으로 제외돼요").font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 160)
            .background(.fill.quaternary, in: .rect(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [6])).foregroundStyle(.separator))
            .opacity(0.5)
        }
    }

    // MARK: 동작

    private func connect() async {
        guard let client = app.client else { return }
        working = true
        defer { working = false }
        do {
            let created = try await client.send(.connectProject(repository: repositoryURL, branch: branch))
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
