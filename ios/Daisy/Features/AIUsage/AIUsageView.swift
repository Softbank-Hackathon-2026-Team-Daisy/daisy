import SwiftUI

/// W-12 AI 사용량 (WR-11): 언제, 얼마나 불렀는지. 읽기 전용 화면이에요.
/// 재사용 배포는 AI를 부르지 않아서 호출 기록이 없어요.
struct AIUsageView: View {
    @Environment(AppModel.self) private var app
    @Environment(Workspace.self) private var workspace
    @State private var report: LoadState<AIUsageReport> = .idle

    var body: some View {
        PageScaffold("AI 사용량",
                     subtitle: "AI를 언제, 얼마나 불렀는지 봐요. 판단이 필요한 생성 · 수정에만 AI를 쓰고, 검증된 스크립트는 재사용해서 호출을 줄여요.") {
            Button { Task { await load() } } label: { Label("새로 고침", systemImage: "arrow.clockwise") }
                .buttonStyle(.glassCircle)
                .help("새로 고침")
        } content: {
            if app.selectedProjectID == nil {
                NoProjectView()
            } else {
                LoadStateView(state: report, retry: { await load() }) { report in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            let summary = report.summary
                            AdaptiveGrid(minimumWidth: 180) {
                                tile("AI 호출", "\(summary.calls)회", "이번 주")
                                tile("토큰", summary.tokens.formatted(), "입력 + 출력")
                                tile("비용", summary.costKrw.map { "₩\($0.formatted())" } ?? "—", costNote(summary))
                                tile("재사용으로 아낀 호출", "\(summary.savedCalls)회",
                                     summary.zeroAiDeployments.map { "AI 0회 배포 \($0)건" } ?? "AI 0회 배포")
                            }
                            SectionCard("호출 기록") {
                                if report.items.isEmpty {
                                    Text("아직 AI를 부른 기록이 없어요").foregroundStyle(.secondary)
                                } else {
                                    ViewThatFits(in: .horizontal) {
                                        table(report.items).frame(minWidth: 720)
                                        list(report.items)
                                    }
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
    }

    /// 비용은 추정치예요. 서버가 적용한 환율을 같이 보여줘요.
    private func costNote(_ summary: AIUsageReport.Summary) -> String {
        let rate = summary.exchangeRate.map { " · 환율 ₩\(Int($0).formatted())" } ?? ""
        return "LLM 기준 추정\(rate)"
    }

    private func tile(_ label: String, _ value: String, _ note: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title.weight(.semibold).monospacedDigit())
            Text(note).font(.caption).foregroundStyle(.secondary)
        }
        .cardStyle()
    }

    /// 웹 열: 시각 · 환경 · 작업 · 시도 · 토큰 · 비용 · 결과
    private func table(_ calls: [AIUsageReport.Call]) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 12) {
            GridRow { Text("시각"); Text("환경"); Text("작업"); Text("시도"); Text("토큰"); Text("비용"); Text("결과") }
                .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Divider()
            ForEach(calls) { call in
                GridRow {
                    time(call).font(.caption.monospacedDigit())
                    EnvTag(type: workspace.type(of: call.targetId))
                    Text(task(call)).font(.subheadline)
                    Text(call.attempt.map { "\($0)/3" } ?? "—").font(.subheadline.monospacedDigit())
                    Text(call.tokens.map { $0.formatted() } ?? "—").font(.subheadline.monospacedDigit())
                    Text(call.costKrw.map { "₩\($0.formatted())" } ?? "—").font(.subheadline.monospacedDigit())
                    resultBadge(call)
                }
            }
        }
    }

    private func list(_ calls: [AIUsageReport.Call]) -> some View {
        VStack(spacing: 0) {
            ForEach(calls) { call in
                VStack(alignment: .leading, spacing: 4) {
                    HStack { EnvTag(type: workspace.type(of: call.targetId)); time(call).font(.caption).foregroundStyle(.secondary); Spacer(); resultBadge(call) }
                    Text(task(call)).font(.subheadline)
                    Text([call.attempt.map { "시도 \($0)/3" }, call.tokens.map { "토큰 \($0.formatted())" }, call.costKrw.map { "₩\($0.formatted())" }]
                        .compactMap { $0 }.joined(separator: " · "))
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
                if call.id != calls.last?.id { Divider() }
            }
        }
    }

    private func time(_ call: AIUsageReport.Call) -> some View {
        Group {
            if let at = call.at { Text(at, format: .dateTime.hour().minute()) } else { Text("—") }
        }
    }

    private func task(_ call: AIUsageReport.Call) -> String {
        switch call.step {
        case .generate: "Terraform 생성"
        case .fix: "Terraform 수정"
        case .unknown: "AI 호출"
        }
    }

    private func resultBadge(_ call: AIUsageReport.Call) -> StatusBadge {
        switch call.status {
        case .succeeded: StatusBadge(text: "통과", color: .green)
        case .failed: StatusBadge(text: "실패", color: .red)
        case .unknown: StatusBadge(text: "확인 전", color: .gray)
        }
    }

    private func load() async {
        guard let client = app.client, let projectID = app.selectedProjectID else { return }
        if report.value == nil { report = .loading }
        do {
            report = .loaded(try await client.send(.aiUsage(projectID: projectID)))
        } catch {
            app.handle(error)
            if report.value == nil { report = .failed(error.localizedDescription) }
        }
    }
}
