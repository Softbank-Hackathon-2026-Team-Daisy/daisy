import SwiftUI

/// W-10 환경: 배포 대상 환경의 연결 상태와 인프라 구성. 환경을 고르는 건 배포할 때(W-04) 해요.
struct EnvironmentsView: View {
    @Environment(AppModel.self) private var app
    @State private var targets: LoadState<[DeployTarget]> = .idle
    @State private var testing: String?
    @State private var toast: ToastMessage?
    @State private var resourcesFor: DeployTarget?

    var body: some View {
        PageScaffold("환경", subtitle: "배포 대상 환경의 연결 상태와 인프라 구성을 봐요. 환경을 고르는 건 배포할 때 해요.") {
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
                            SectionCard("환경 추가") {
                                Text("퍼블릭 클라우드(소규모 사업자 포함)나 다른 온프레미스 서버를 대상 환경으로 추가해요. 준비된 기준 모듈이 없어도 AI가 deploy.yaml로 Terraform을 처음부터 만들어요.")
                                    .font(.subheadline).foregroundStyle(.secondary)
                                // 웹도 추가 흐름 화면이 아직 없어요 (예선 범위 결정 대기)
                                Button { } label: { Label("환경 추가", systemImage: "plus") }
                                    .buttonStyle(.glassCapsule)
                                    .disabled(true)
                                    .help("환경 추가 흐름은 예선 범위 결정 뒤에 열려요")
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

    private func panel(_ target: DeployTarget) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                EnvTag(type: target.type)
                Spacer()
                target.connected == false
                    ? StatusBadge(text: "연결 끊김", color: .red)
                    : StatusBadge(text: "연결됨", color: .green)
            }
            InfoRow("유형", target.runtime)
            InfoRow(target.type == .onprem ? "위치" : "리전", target.location)
            InfoRow("연결", target.connection)
            InfoRow("공개", target.exposure)
            InfoRow("state", target.stateBackend)
            InfoRow("현재 버전", target.currentCommit.map { String($0.prefix(7)) }, monospaced: true)
            HStack(spacing: 8) {
                Button {
                    Task { await test(target) }
                } label: {
                    if testing == target.id { ProgressView().controlSize(.small) } else { Text("연결 테스트") }
                }
                .buttonStyle(.glassCapsule)
                .disabled(testing != nil)
                Button("리소스 보기") { resourcesFor = target }
                    .buttonStyle(.glassCapsule)
            }
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
            toast = result.connected
                ? ToastMessage(kind: .success, title: "\(target.type.displayName) 연결됨", message: result.message)
                : ToastMessage(kind: .danger, title: "\(target.type.displayName) 연결 끊김", message: result.message)
        } catch {
            app.handle(error)
            toast = ToastMessage(kind: .danger, title: "연결을 확인하지 못했어요", message: error.localizedDescription)
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
                List(list, id: \.self) { resource in
                    VStack(alignment: .leading) {
                        Text(resource.address).font(.subheadline.monospaced())
                        if let type = resource.type { Text(type).font(.caption).foregroundStyle(.secondary) }
                    }
                }
                .overlay { if list.isEmpty { ContentUnavailableView("리소스가 없어요", systemImage: "square.stack.3d.up") } }
            }
            .navigationTitle("\(target.type.displayName) 리소스")
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
