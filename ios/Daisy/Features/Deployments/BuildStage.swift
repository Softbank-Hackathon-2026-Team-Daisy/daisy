import SwiftUI

/// W-03 이미지 빌드: GitHub Actions 단계와 이미지 정보. 다음 버튼은 없고 빌드가 끝나면 서버가 다음 단계로 넘겨요 (Q4).
struct BuildStage: View {
    let deployment: Deployment
    @Environment(AppModel.self) private var app
    @Environment(Workspace.self) private var workspace
    @Environment(\.openURL) private var openURL
    @State private var build: Build?

    var body: some View {
        FlowPage(step: 2, title: "이미지 빌드",
                 description: "main merge를 감지했어요. GitHub Actions가 이미지를 만들고 있어요.") {
            RunListItem(deployment: deployment).cardStyle()
            AdaptiveGrid(minimumWidth: 320) {
                SectionCard("GitHub Actions") {
                    let steps = build?.steps ?? []
                    if steps.isEmpty {
                        Text("단계 정보를 기다리고 있어요").foregroundStyle(.secondary)
                    }
                    ForEach(steps, id: \.self) { StepItemRow($0) }
                    Button("Actions 로그 열기") {
                        if let url = build?.pipeline.runUrl { openURL(url) }
                    }
                    .buttonStyle(.glassCapsule)
                    .disabled(build?.pipeline.runUrl == nil)
                }
                SectionCard("이미지") {
                    InfoRow("커밋", String(deployment.commit.prefix(7)), monospaced: true)
                    InfoRow("브랜치", build?.branch ?? workspace.project?.branch, monospaced: true)
                    InfoRow("이미지", deployment.image ?? build?.image, monospaced: true)
                    InfoRow("digest", build?.digest, monospaced: true)
                    ConnectionIndicator(state: workspace.connection)
                }
            }
        }
        .task(id: deployment.commit) { await poll(every: 5) { await loadBuild() } }
    }

    private func loadBuild() async {
        guard let client = app.client else { return }
        let builds = try? await client.send(.builds(projectID: deployment.projectId)).items
        build = builds?.first { $0.commit == deployment.commit } ?? build
    }
}
