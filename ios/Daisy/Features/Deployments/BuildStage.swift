import SwiftUI

/// W-03 이미지 빌드: Jenkins CI(`daisy-ci`) 단계와 이미지 정보 (A-06).
/// 배포가 생기기 전 단계예요. 빌드가 성공하면 이 커밋으로 W-04 환경 선택에 넘어가요 (Q4 결정 전 가정).
/// 사이드바 "새 배포"는 커밋 없이 열어서 가장 최근 빌드를 보여줘요 (웹 사이드바 "새 배포" → W-03).
struct BuildStage: View {
    var commit: String? = nil
    @Environment(AppModel.self) private var app
    @Environment(Router.self) private var router
    @Environment(Workspace.self) private var workspace
    @State private var build: Build?

    var body: some View {
        FlowPage(step: 2, title: "이미지 빌드",
                 description: "main merge를 감지했어요. Jenkins가 이미지를 만들고 있어요.") {
            HStack(spacing: 10) {
                pipelineBadge
                if let current { CommitLabel(commit: current) }
                Text(build?.message ?? "").font(.subheadline).lineLimit(1)
                Spacer(minLength: 8)
                if let author = build?.author { Avatar(name: author) }
            }
            .cardStyle()
            AdaptiveGrid(minimumWidth: 320) {
                SectionCard("Jenkins CI") {
                    let steps = build?.steps ?? []
                    if steps.isEmpty {
                        Text("단계 정보를 기다리고 있어요").foregroundStyle(.secondary)
                    }
                    // Jenkins 화면은 배포 키가 있어서 외부에 공개하지 않아요 → 로그 열기 버튼 없음 (10/1 임채준 답, PR #17)
                    ForEach(steps, id: \.self) { StepItemRow($0) }
                }
                SectionCard("이미지") {
                    InfoRow("커밋", current.map { String($0.prefix(7)) }, monospaced: true)
                    InfoRow("브랜치", build?.branch ?? workspace.project?.branch, monospaced: true)
                    InfoRow("이미지", build?.image, monospaced: true)
                    InfoRow("digest", build?.digest, monospaced: true)
                    ConnectionIndicator(state: workspace.connection)
                }
            }
            if build?.pipeline.status == .failed {
                InlineAlert(.danger, "빌드 · 테스트가 실패했어요", "빌드 단계에서 원인을 확인해 주세요. 실패한 이미지는 배포하지 않아요.")
            }
        }
        // 빌드가 끝나면(성공 · 실패) 멈춰요
        .task(id: commit) { await poll(until: { [.success, .failed].contains(build?.pipeline.status) }) { await loadBuild() } }
    }

    /// 보여줄 커밋: 넘겨받은 커밋, 없으면 가장 최근 빌드
    private var current: String? { commit ?? build?.commit }

    private var pipelineBadge: StatusBadge {
        switch build?.pipeline.status {
        case .success: StatusBadge(text: "빌드 완료", color: .green)
        case .failed: StatusBadge(text: "빌드 실패", color: .red)
        default: StatusBadge(text: "빌드 중", color: .blue)
        }
    }

    private func loadBuild() async {
        guard let client = app.client, let projectID = app.selectedProjectID else { return }
        let builds = try? await client.send(.builds(projectID: projectID)).items
        build = builds?.first { commit == nil || $0.commit == commit } ?? build
        if build?.pipeline.status == .success, build?.image != nil, let current {
            router.replaceTop(with: .selectTargets(commit: current))
        }
    }
}
