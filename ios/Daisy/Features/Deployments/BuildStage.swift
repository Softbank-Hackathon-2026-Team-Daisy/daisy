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
    /// `build`를 받은 프로젝트. 프로젝트를 바꾸면 이전 빌드를 지워요 (D6)
    @State private var buildProject: String?
    /// 빌드 목록을 받지 못했어요 (D7). 처음이면 안내, 받은 뒤면 머리줄에 작게
    @State private var errorMessage: String?

    var body: some View {
        FlowPage(step: 2, title: .app("이미지 빌드"),
                 description: .app("main merge를 감지했어요. Jenkins가 이미지를 만들고 있어요.")) {
            HStack(spacing: 10) {
                pipelineBadge
                if let current { CommitLabel(commit: current) }
                Text(build.map { $0.message ?? "—" } ?? "").font(.subheadline).lineLimit(1)
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
                SectionCard(.app("이미지")) {
                    InfoRow(.app("커밋"), current.map { String($0.prefix(7)) }, monospaced: true)
                    InfoRow(.app("브랜치"), build?.branch ?? workspace.project?.branch, monospaced: true)
                    InfoRow(.app("이미지"), build?.image, monospaced: true)
                    InfoRow("digest", build?.imageDigest, monospaced: true)
                    ConnectionIndicator(state: workspace.connection)
                }
            }
            if build == nil, let errorMessage {
                InlineAlert(.danger, .app("빌드 정보를 불러오지 못했어요"), errorMessage)
            }
            if build?.pipeline.status == .failed {
                InlineAlert(.danger, .app("빌드 · 테스트가 실패했어요"), .app("빌드 단계에서 원인을 확인해 주세요. 실패한 이미지는 배포하지 않아요."))
            }
        }
        .environment(\.flowRefreshIssue, build == nil ? nil : errorMessage.map { message in
            FlowRefreshIssue(message: message) { await loadBuild() }
        })
        // `build.received`(프로젝트 채널)가 오면 바로 다시 불러요. Jenkins 단계 진행은 이벤트가 없어서 진행 중이면 5초 폴링이에요.
        // 커밋을 정해 들어왔으면 그 빌드가 끝나면(성공 · 실패) 멈춰요. 사이드바 "새 배포"(커밋 없음)는 가장 최근 빌드가 실패여도
        // 다음 빌드를 계속 기다려요 (D5) — 끝난 동안은 SSE 15초 · 끊기면 5초. 프로젝트가 바뀌면 다시 시작해요 (D6)
        .task(id: BuildKey(commit: commit, projectID: app.selectedProjectID)) {
            await poll(on: workspace.live.changes,
                       every: { isBuildFinished ? PollInterval.seconds(live: workspace.live.isLive) : PollInterval.normal },
                       until: { commit != nil && isBuildFinished }) { await loadBuild() }
        }
    }

    /// 보여줄 커밋: 넘겨받은 커밋, 없으면 가장 최근 빌드
    private var current: String? { commit ?? build?.commit }

    private var pipelineBadge: StatusBadge {
        switch build?.pipeline.status {
        case .success: StatusBadge(text: .app("빌드 완료"), color: .green)
        case .failed: StatusBadge(text: .app("빌드 실패"), color: .red)
        case .queued: StatusBadge(text: .app("대기 중"), color: .gray)
        default: StatusBadge(text: .app("빌드 중"), color: .blue)
        }
    }

    private var isBuildFinished: Bool { [.success, .failed].contains(build?.pipeline.status) }

    private func loadBuild() async {
        guard let client = app.client, let projectID = app.selectedProjectID else { return }
        if buildProject != projectID { (build, buildProject) = (nil, projectID) }
        let tab = router.tab
        do {
            let builds = try await client.send(.builds(projectID: projectID)).items
            // 기다리는 동안 프로젝트를 바꿨으면 늦게 온 응답은 버려요
            guard !Task.isCancelled, app.selectedProjectID == projectID else { return }
            build = builds.first { commit == nil || $0.commit == commit } ?? build
            errorMessage = nil
        } catch {
            if Task.isCancelled { return }
            app.handle(error)
            errorMessage = error.localizedDescription
            return
        }
        if build?.pipeline.status == .success, build?.image != nil, let current {
            router.replaceTop(with: .selectTargets(commit: current), in: tab)
        }
    }
}

/// 빌드를 다시 찾을 때: 커밋 · 프로젝트가 바뀌면 (D6)
private struct BuildKey: Equatable {
    let commit: String?
    let projectID: String?
}
