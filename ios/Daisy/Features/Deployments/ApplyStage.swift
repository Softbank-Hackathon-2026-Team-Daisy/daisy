import SwiftUI

/// W-07 배포 중: 환경별 레인(나란히) + 전체 환경 로그. 다 끝나면 결과(W-08)로 넘어가요 (`RunStage`).
/// 레인 배지는 환경별 상태 그대로, 단계는 서버 `steps`가 없으면 웹처럼 "이미지 pull · terraform apply · state 저장 · 헬스체크".
struct ApplyStage: View {
    let deployment: Deployment
    /// 배포 채널. `log.batch`가 오면 로그를 바로 다시 불러요
    var live: LiveChannel?
    @Environment(AppModel.self) private var app
    @Environment(Workspace.self) private var workspace
    @State private var lines: [LogLine] = []
    @State private var autoScroll = true

    private var targets: [Deployment.Target] { deployment.targets ?? [] }

    var body: some View {
        FlowPage(step: 5, title: .app("배포 중"),
                 description: .app("\(targets.count)개 환경에 terraform apply를 동시에 실행하고 있어요. 환경마다 state는 따로 저장해요.")) {
            HStack { deployment.badge; Spacer() }
            AdaptiveGrid(minimumWidth: 260) {
                ForEach(targets) { lane($0) }
            }
            LogViewer(lines: lines, autoScroll: $autoScroll) { workspace.type(of: $0).logSource }
        }
        .task {
            await poll(on: live?.logs, every: { PollInterval.seconds(live: live?.isLive == true, active: deployment.state.isActive) }) {
                await loadLogs()
            }
        }
    }

    private func lane(_ target: Deployment.Target) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(workspace.name(of: target.targetId)).font(.headline)
                    if let title = target.title {
                        Text(title).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                target.resolvedState.badge
            }
            ForEach(target.applySteps, id: \.self) { StepItemRow($0) }
        }
        .cardStyle()
    }

    private func loadLogs() async {
        guard let client = app.client else { return }
        do {
            lines = try await client.send(.logs(deploymentID: deployment.id)).items
        } catch {
            // 로그는 보조 정보라 마지막으로 받은 줄을 그대로 두고, 로그인 만료만 처리해요 (X2)
            if !Task.isCancelled { app.handle(error) }
        }
    }
}

/// 웹 Log Viewer: "로그 · 전체 환경" + 자동 스크롤. 시각 · 출처 · 레벨 · 메시지.
struct LogViewer: View {
    let lines: [LogLine]
    @Binding var autoScroll: Bool
    let source: (String) -> String

    var body: some View {
        SectionCard(.app("로그 · 전체 환경")) {
            Button(autoScroll ? "자동 스크롤 켜짐" : "자동 스크롤 꺼짐") { autoScroll.toggle() }
                .buttonStyle(.glassCapsule)
        } content: {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        if lines.isEmpty {
                            Text("아직 로그가 없어요").font(.caption).foregroundStyle(.secondary)
                        }
                        ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                            logLine(line).id(index)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minHeight: 140, maxHeight: 260)
                .onChange(of: lines.count) { _, count in
                    if autoScroll, count > 0 { withAnimation { proxy.scrollTo(count - 1, anchor: .bottom) } }
                }
            }
        }
    }

    private func logLine(_ line: LogLine) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(line.ts.map { TimeText.clockSeconds($0) } ?? "")
                .foregroundStyle(.secondary)
            Text(line.targetId.map(source) ?? "").frame(width: 50, alignment: .leading).foregroundStyle(.secondary)
            Text(line.level.uppercased()).frame(width: 44, alignment: .leading)
                .foregroundStyle(line.level.lowercased() == "error" ? .red : line.level.lowercased() == "warn" ? .orange : .secondary)
            Text(line.text).textSelection(.enabled)
        }
        .font(.caption.monospaced())
    }
}

/// 로그 전체 화면: W-05b "오류 로그 보기", W-08 "원인 보기".
/// 진행 중인 배포면 배포 채널의 `log.batch`가 오면 바로(다른 배포 채널이 이미 열려 있으면 5초 폴링), 끝난 배포면 끝난 뒤 한 번 받고 멈춰요 (D16).
struct LogsView: View {
    let deploymentID: String
    let targetID: String?
    @Environment(AppModel.self) private var app
    @Environment(Workspace.self) private var workspace
    @State private var lines: [LogLine] = []
    @State private var autoScroll = true
    /// 배포 상태. 끝났으면 더 받지 않아요
    @State private var state: DeploymentState?
    @State private var loadedOnce = false
    @State private var errorMessage: String?
    @State private var channel = LiveChannel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let errorMessage {
                    if loadedOnce {
                        StaleNotice(issue: FlowRefreshIssue(message: errorMessage) { await load() })
                    } else {
                        InlineAlert(.danger, .app("로그를 불러오지 못했어요"), errorMessage)
                        Button("다시 시도") { Task { await load() } }.buttonStyle(.glassCapsule)
                    }
                }
                LogViewer(lines: lines, autoScroll: $autoScroll) { workspace.type(of: $0).logSource }
            }
            .padding(20)
        }
        .navigationTitle(targetID.map { String.app("\(workspace.name(of: $0)) 로그") } ?? String.app("로그"))
        .task {
            await poll(on: channel.logs, every: { state == .unknown ? RunRefresh.unknownInterval : PollInterval.seconds(live: channel.isLive) },
                       until: { loadedOnce && state?.isFinished == true }) { await load() }
        }
        // 진행 중일 때만 배포 채널을 열어요. 밑에 깔린 배포 화면이 이미 열어 뒀으면 폴링으로 버텨요 (앱은 한 번에 하나)
        .task(id: state?.isActive == true) {
            guard state?.isActive == true, !workspace.projectChannelPaused, let stream = app.eventStream else { return }
            channel.onChange = { [workspace] in workspace.refreshSoon() }
            workspace.hold(channel)
            defer { workspace.release(channel) }
            await channel.listen(stream, path: "deployments/\(deploymentID)/events")
        }
    }

    /// 배포 상태를 먼저 받고 로그를 받아요. 끝난 배포면 이 로그가 마지막이에요
    private func load() async {
        guard let client = app.client else { return }
        do {
            state = try await client.send(.deployment(id: deploymentID)).state
            lines = try await client.send(.logs(deploymentID: deploymentID, targetID: targetID, tail: 500)).items
            loadedOnce = true
            errorMessage = nil
        } catch {
            if Task.isCancelled { return }
            app.handle(error)
            errorMessage = error.localizedDescription
        }
    }
}
