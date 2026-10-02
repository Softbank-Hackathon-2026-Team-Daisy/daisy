import SwiftUI

/// W-10 환경: 배포 대상 환경의 연결 상태와 인프라 구성. 환경을 고르는 건 배포할 때(W-04) 해요.
struct EnvironmentsView: View {
    @Environment(AppModel.self) private var app
    @State private var targets: LoadState<[DeployTarget]> = .idle
    @State private var testing: String?
    @State private var toast: ToastMessage?
    @State private var resourcesFor: DeployTarget?

    var body: some View {
        PageScaffold(.app("환경"), subtitle: .app("배포 대상 환경의 연결 상태와 인프라 구성을 봐요. 환경을 고르는 건 배포할 때 해요.")) {
            Button { Task { await load() } } label: { Label("새로 고침", systemImage: "arrow.clockwise") }
                .buttonStyle(.glassCircle)
                .help("새로 고침")
        } content: {
            if app.selectedProjectID == nil {
                NoProjectView()
            } else {
                LoadStateView(state: targets, retry: { await load() }) { targets in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            AdaptiveGrid(minimumWidth: 280) {
                                ForEach(targets) { panel($0) }
                            }
                            SectionCard(.app("환경 추가")) {
                                Text("퍼블릭 클라우드(소규모 사업자 포함)나 다른 온프레미스 서버를 대상 환경으로 추가해요. 준비된 기준 모듈이 없어도 AI가 deploy.yaml로 Terraform을 처음부터 만들어요.")
                                    .font(.subheadline).foregroundStyle(.secondary)
                                // 웹도 추가 흐름 화면이 없어요. 예선은 4개 환경 (10/2 회의, 웹 #87)
                                ViewThatFits(in: .horizontal) {
                                    HStack(spacing: 10) { addButton; roundNote }
                                    VStack(alignment: .leading, spacing: 8) { addButton; roundNote }
                                }
                            }
                        }
                        .padding(20)
                    }
                    .refreshable { await load() }
                }
            }
        }
        .task(id: app.selectedProjectID) { await load() }
        .toast($toast)
        .sheet(item: $resourcesFor) { ResourcesSheet(target: $0) }
    }

    /// 연결 테스트(A-10) · 리소스 보기(A-11)는 가칭(#13 후순위)이라 개발 서버에 없어요 (누르면 404).
    /// 웹처럼 실서버에서는 꺼 둬요. 서버에 생기면 `Endpoint.targetProbesOnServer`를 켜요
    private var probeReady: Bool { Endpoint<EmptyResponse>.targetProbesOnServer }

    private var addButton: some View {
        Button { } label: { Label("환경 추가", systemImage: "plus") }
            .buttonStyle(.glassCapsule)
            .disabled(true)
    }

    private var roundNote: some View {
        Text("예선에서는 온프레미스 · AWS · GCP · Azure 4개 환경을 써요").font(.caption).foregroundStyle(.secondary)
    }

    private func panel(_ target: DeployTarget) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                EnvTag(type: target.type)
                Spacer()
                switch target.connection?.state {
                case .ok: StatusBadge(text: .app("연결됨"), color: .green)
                case .failed: StatusBadge(text: .app("연결 안 됨"), color: .red)
                default: StatusBadge(text: .app("확인 전"), color: .gray)
                }
            }
            InfoRow(.app("유형"), target.runtime ?? target.title)
            InfoRow(target.locationLabel ?? (target.type == .onprem ? String.app("위치") : String.app("리전")), target.location)
            InfoRow(.app("연결"), target.accessMethod)
            InfoRow(.app("공개"), target.exposure)
            // state 저장소는 인프라가 아직 정하지 않았어요 (10/1, 키 방향만 {project_id}/{target_id})
            InfoRow("state", target.stateBackend ?? String.app("[미정]"))
            InfoRow(.app("현재 버전"), target.currentCommit.map { String($0.prefix(7)) }, monospaced: true)
            HStack(spacing: 8) {
                Button {
                    Task { await test(target) }
                } label: {
                    if testing == target.id { ProgressView().controlSize(.small) } else { Text("연결 테스트") }
                }
                .buttonStyle(.glassCapsule)
                .disabled(testing != nil || !probeReady)
                Button("리소스 보기") { resourcesFor = target }
                    .buttonStyle(.glassCapsule)
                    .disabled(!probeReady)
            }
            .help(probeReady ? "" : String.app("서버에 아직 없는 기능이에요"))
        }
        .cardStyle()
    }

    private func load() async {
        guard let client = app.client, let projectID = app.selectedProjectID else { return }
        if targets.value == nil { targets = .loading }
        do {
            targets = .loaded(try await client.send(.deployTargets(projectID: projectID)).items)
        } catch {
            app.handle(error)
            if targets.value == nil { targets = .failed(error.localizedDescription) }
        }
    }

    private func test(_ target: DeployTarget) async {
        guard let client = app.client else { return }
        testing = target.id
        defer { testing = nil }
        do {
            let result = try await client.send(.testConnection(targetID: target.id))
            // 웹: 서버 메시지를 그대로 제목으로
            toast = ToastMessage(kind: result.connected ? .success : .danger, title: result.message ?? (result.connected ? String.app("연결됨") : String.app("연결 안 됨")))
        } catch {
            app.handle(error)
            toast = ToastMessage(kind: .danger, title: .app("연결 테스트를 하지 못했어요"), message: error.localizedDescription)
        }
    }
}

/// "리소스 보기": 이 환경의 인프라 리소스 목록
private struct ResourcesSheet: View {
    let target: DeployTarget
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var resources: LoadState<[EnvironmentResource]> = .idle

    var body: some View {
        NavigationStack {
            LoadStateView(state: resources, retry: { await load() }) { list in
                List {
                    Section {
                        ForEach(list, id: \.self) { resource in
                            VStack(alignment: .leading) {
                                Text(resource.address).font(.subheadline.monospaced())
                                if let type = resource.type { Text(type).font(.caption).foregroundStyle(.secondary) }
                            }
                        }
                    } footer: {
                        Text("Terraform state에 기록된 리소스예요.")
                    }
                }
                .overlay { if list.isEmpty { ContentUnavailableView("리소스가 없어요", systemImage: "square.stack.3d.up") } }
            }
            .navigationTitle("\(target.title ?? target.name) 리소스")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("닫기") { dismiss() } }
            }
        }
        .frame(minWidth: 420, minHeight: 360)
        .task { await load() }
    }

    private func load() async {
        guard let client = app.client else { return }
        resources = .loading
        do {
            resources = .loaded(try await client.send(.targetResources(targetID: target.id)).items)
        } catch {
            app.handle(error)
            resources = .failed(error.localizedDescription)
        }
    }
}
