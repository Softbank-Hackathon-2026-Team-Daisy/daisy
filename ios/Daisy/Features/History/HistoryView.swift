import SwiftUI
import Observation

/// 커밋 · 파이프라인 이력 (A-06, 서버 D3 제공).
@MainActor
@Observable
final class HistoryStore {
    private(set) var builds: LoadState<[Build]> = .idle

    func refresh(using app: AppModel) async {
        guard let client = app.client, let projectID = app.selectedProjectID else { return }
        if builds.value == nil { builds = .loading }
        do {
            builds = .loaded(try await client.send(.builds(projectID: projectID)).items)
        } catch {
            app.handle(error)
            if builds.value == nil { builds = .failed(error.localizedDescription) }
        }
    }
}

/// 5 커밋 · 파이프라인: 이 커밋이 빌드됐는지, 어느 환경까지 나갔는지.
struct HistoryView: View {
    @Environment(AppModel.self) private var app
    @State private var store = HistoryStore()

    var body: some View {
        Group {
            if app.client == nil {
                NotConnectedView()
            } else if app.selectedProjectID == nil {
                NoProjectView()
            } else {
                LoadStateView(state: store.builds, retry: { await store.refresh(using: app) }) { builds in
                    List(builds) { BuildRow(build: $0) }
                        .overlay {
                            if builds.isEmpty {
                                ContentUnavailableView("빌드 기록이 없어요", systemImage: "hammer")
                            }
                        }
                        .refreshable { await store.refresh(using: app) }
                }
            }
        }
        .navigationTitle("커밋")
        .task(id: app.selectedProjectID) { await store.refresh(using: app) }
    }
}

struct BuildRow: View {
    let build: Build

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                CommitLabel(commit: build.commit)
                Spacer()
                build.pipeline.status.badge
            }
            Text(build.message).lineLimit(2)
            HStack(spacing: 6) {
                Text(build.author)
                if let committedAt = build.committedAt {
                    Text(committedAt, format: .relative(presentation: .named))
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            if !build.deployedTo.isEmpty {
                Text("배포된 환경: " + build.deployedTo.map(\.targetId).joined(separator: ", "))
                    .font(.caption)
            }
            if let runURL = build.pipeline.runUrl {
                Link("Actions 실행 보기", destination: runURL).font(.caption)
            }
        }
    }
}
