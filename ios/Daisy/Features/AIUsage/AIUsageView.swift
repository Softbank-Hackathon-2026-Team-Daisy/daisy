import SwiftUI

/// W-12 AI 사용량: 언제, 얼마나 불렀는지. 읽기 전용 화면이에요.
struct AIUsageView: View {
    @Environment(AppModel.self) private var app
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
                            AdaptiveGrid(minimumWidth: 180) {
                                tile("AI 호출", "\(report.calls)회", "이번 주")
                                tile("토큰", report.tokens.formatted(), "입력 + 출력")
                                tile("비용", report.costKrw.map { "₩\($0.formatted())" } ?? "—", "LLM 기준 추정")
                                tile("재사용으로 아낀 호출", "\(report.savedCalls)회", "AI 0회 배포")
                            }
                            SectionCard("호출 기록") {
                                if report.history.isEmpty {
                                    Text("아직 AI를 부른 기록이 없어요").foregroundStyle(.secondary)
                                } else {
                                    ViewThatFits(in: .horizontal) {
                                        table(report.history).frame(minWidth: 720)
                                        list(report.history)
                                    }
                                }
                            }
                            InlineAlert(.info, "PoC N-09 (선택)", "비용 표시는 N-09 결과와 LLM 선택에 따라 달라져요. 범위에서 빠지면 호출 수 · 토큰만 보여줘요.")
                        }
                        .padding(20)
                    }
                    .refreshable { await load() }
                }
            }
        }
        .task(id: app.selectedProjectID) { await load() }
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
                    EnvTag(type: call.targetType)
                    Text(call.task).font(.subheadline)
                    Text(call.attempt.map { "\($0)/3" } ?? "—").font(.subheadline.monospacedDigit())
                    Text(call.tokens.formatted()).font(.subheadline.monospacedDigit())
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
                    HStack { EnvTag(type: call.targetType); time(call).font(.caption).foregroundStyle(.secondary); Spacer(); resultBadge(call) }
                    Text(call.task).font(.subheadline)
                    Text([call.attempt.map { "시도 \($0)/3" }, "토큰 \(call.tokens.formatted())", call.costKrw.map { "₩\($0.formatted())" }]
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

    /// 웹: plan 통과 · 통과 · AI 호출 없음 · 실패 · 중단
    private func resultBadge(_ call: AIUsageReport.Call) -> StatusBadge {
        switch call.ok {
        case true: StatusBadge(text: call.result, color: .green)
        case false: StatusBadge(text: call.result, color: .red)
        case nil: StatusBadge(text: call.result, color: .gray)
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
