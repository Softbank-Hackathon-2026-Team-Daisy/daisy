import SwiftUI

/// W-07 배포 중: 환경별 레인(나란히) + 전체 환경 로그. 다 끝나면 서버가 결과(W-08)로 넘겨요.
struct ApplyStage: View {
    let deployment: Deployment
    @Environment(AppModel.self) private var app
    @Environment(Workspace.self) private var workspace
    @State private var lines: [LogLine] = []
    @State private var autoScroll = true

    private var targets: [Deployment.Target] { deployment.targets ?? [] }

    var body: some View {
        FlowPage(step: 5, title: "배포 중",
                 description: "\(targets.count)개 환경에 terraform apply를 동시에 실행하고 있어요. 환경마다 state는 따로 저장해요.") {
            AdaptiveGrid(minimumWidth: 260) {
                ForEach(targets) { lane($0) }
            }
            LogViewer(lines: lines, autoScroll: $autoScroll) { workspace.type(of: $0).logSource }
        }
        .task { await poll { await loadLogs() } }
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
                laneBadge(target)
            }
            ForEach(target.steps ?? [], id: \.self) { StepItemRow($0) }
            if (target.steps ?? []).isEmpty {
                StepItemRow(name: target.step.displayName, state: target.stepState)
            }
        }
        .cardStyle()
    }

    /// 웹: 배포 중 · 성공 · 실패
    private func laneBadge(_ target: Deployment.Target) -> StatusBadge {
        switch target.stepState {
        case .failed: StatusBadge(text: "실패", color: .red)
        case .done where target.step == .healthCheck: StatusBadge(text: "성공", color: .green)
        default: StatusBadge(text: "배포 중", color: .blue)
        }
    }

    private func loadLogs() async {
        guard let client = app.client else { return }
        if let page = try? await client.send(.logs(deploymentID: deployment.id)) { lines = page.items }
    }
}

/// 웹 Log Viewer: "로그 · 전체 환경" + 자동 스크롤. 시각 · 출처 · 레벨 · 메시지.
struct LogViewer: View {
    let lines: [LogLine]
    @Binding var autoScroll: Bool
    let source: (String) -> String

    var body: some View {
        SectionCard("로그 · 전체 환경") {
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
            Text(line.ts.map { $0.formatted(date: .omitted, time: .standard) } ?? "")
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
struct LogsView: View {
    let deploymentID: String
    let targetID: String?
    @Environment(AppModel.self) private var app
    @Environment(Workspace.self) private var workspace
    @State private var lines: [LogLine] = []
    @State private var autoScroll = true

    var body: some View {
        ScrollView {
            LogViewer(lines: lines, autoScroll: $autoScroll) { workspace.type(of: $0).logSource }
                .padding(20)
        }
        .navigationTitle(targetID.map { "\(workspace.name(of: $0)) 로그" } ?? "로그")
        .task { await poll { await load() } }
    }

    private func load() async {
        guard let client = app.client else { return }
        if let page = try? await client.send(.logs(deploymentID: deploymentID, targetID: targetID, tail: 500)) {
            lines = page.items
        }
    }
}
