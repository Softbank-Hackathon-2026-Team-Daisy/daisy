import SwiftUI

/// W-12 AI 사용량 — 배포 단위 (9/30 와이어프레임 수정). 배포를 하나 골라서 그 배포의 `ai_usage`(A-04)를 봐요.
/// 재사용으로 AI를 안 부른 환경은 호출 기록이 없어서 "— 검증된 스크립트 재사용" 한 줄로 보여줘요. 규칙은 `AIUsageSummary`.
struct AIUsageView: View {
    @Environment(AppModel.self) private var app
    @Environment(Workspace.self) private var workspace
    @State private var deployments: [Deployment] = []
    @State private var selectedID: String?
    @State private var detail: LoadState<Deployment> = .idle

    var body: some View {
        PageScaffold("AI 사용량",
                     subtitle: "배포마다 AI를 몇 번, 얼마나 썼는지 봐요. 판단이 필요한 생성 · 수정에만 AI를 쓰고, 검증된 스크립트는 재사용해요.") {
            deploymentPicker
            Button { Task { await loadList(); await loadDetail() } } label: { Label("새로 고침", systemImage: "arrow.clockwise") }
                .buttonStyle(.glassCircle)
                .help("새로 고침")
        } content: {
            if app.selectedProjectID == nil {
                NoProjectView()
            } else if deployments.isEmpty && detail.value == nil {
                ContentUnavailableView("아직 배포가 없어요", systemImage: "cellularbars",
                                       description: Text("배포를 한 번 하면 AI를 몇 번 불렀는지 여기서 볼 수 있어요."))
            } else {
                LoadStateView(state: detail, retry: { await loadDetail() }) { deployment in
                    content(AIUsageSummary(deployment))
                }
            }
        }
        .task(id: app.selectedProjectID) {
            await loadList()
            await loadDetail()
        }
        .onChange(of: selectedID) { Task { await loadDetail() } }
    }

    // MARK: 배포 고르기 (웹 Select "dep_42 · a1b2c3d · 21:10 배포")

    private var deploymentPicker: some View {
        Menu {
            ForEach(deployments) { deployment in
                Button(AIUsageSummary.pickerTitle(deployment)) { selectedID = deployment.id }
            }
        } label: {
            Label(deployments.first { $0.id == selectedID }.map(AIUsageSummary.pickerTitle) ?? "배포 선택",
                  systemImage: "arrow.triangle.branch")
        }
        .menuStyle(.button)
        .buttonStyle(.glassCapsule)
        .fixedSize()
        .disabled(deployments.isEmpty)
    }

    // MARK: 내용

    private func content(_ summary: AIUsageSummary) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                AdaptiveGrid(minimumWidth: 180) {
                    tile("AI 호출", "\(summary.calls)회", "이번 배포")
                    tile("토큰", summary.tokens.formatted(), "입력 + 출력")
                    tile("비용", summary.costKrw.map { "₩\($0.formatted())" } ?? "—", costNote(summary))
                    tile("재사용한 환경", "\(summary.reusedTargetIDs.count)곳", reuseNote(summary))
                }
                SectionCard("이 배포의 호출 기록") {
                    if summary.rows.isEmpty {
                        Text("이 배포는 AI를 부르지 않았어요").foregroundStyle(.secondary)
                    } else {
                        ViewThatFits(in: .horizontal) {
                            table(summary.rows).frame(minWidth: 720)
                            list(summary.rows)
                        }
                    }
                }
                InlineAlert(.info, "PoC N-09 (선택)", "비용 표시는 N-09 결과와 LLM 선택에 따라 달라져요. 범위에서 빠지면 호출 수 · 토큰만 보여줘요.")
            }
            .padding(20)
        }
        .refreshable { await loadDetail() }
    }

    /// 비용은 추정치예요. 서버가 적용한 환율을 같이 보여줘요.
    private func costNote(_ summary: AIUsageSummary) -> String {
        let rate = summary.exchangeRate.map { " · 환율 ₩\(Int($0).formatted())" } ?? ""
        return "LLM 기준 추정\(rate)"
    }

    /// 웹: "온프레미스 · AI 호출 0회"
    private func reuseNote(_ summary: AIUsageSummary) -> String {
        guard !summary.reusedTargetIDs.isEmpty else { return "모든 환경이 AI로 생성" }
        return FlowCopy.join(summary.reusedTargetIDs.map { workspace.name(of: $0) }) + " · AI 호출 0회"
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
    private func table(_ rows: [AIUsageSummary.Row]) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 12) {
            GridRow { Text("시각"); Text("환경"); Text("작업"); Text("시도"); Text("토큰"); Text("비용"); Text("결과") }
                .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Divider()
            ForEach(rows) { row in
                GridRow {
                    time(row).font(.caption.monospacedDigit())
                    EnvTag(type: workspace.type(of: row.targetID))
                    Text(row.task).font(.subheadline)
                    Text(row.attempt).font(.subheadline.monospacedDigit())
                    Text(row.tokens.formatted()).font(.subheadline.monospacedDigit())
                    Text(row.costKrw.map { "₩\($0.formatted())" } ?? "—").font(.subheadline.monospacedDigit())
                    badge(row.result)
                }
            }
        }
    }

    private func list(_ rows: [AIUsageSummary.Row]) -> some View {
        VStack(spacing: 0) {
            ForEach(rows) { row in
                VStack(alignment: .leading, spacing: 4) {
                    HStack { EnvTag(type: workspace.type(of: row.targetID)); time(row).font(.caption).foregroundStyle(.secondary); Spacer(); badge(row.result) }
                    Text(row.task).font(.subheadline)
                    Text(["시도 \(row.attempt)", "토큰 \(row.tokens.formatted())", row.costKrw.map { "₩\($0.formatted())" }]
                        .compactMap { $0 }.joined(separator: " · "))
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
                if row.id != rows.last?.id { Divider() }
            }
        }
    }

    private func time(_ row: AIUsageSummary.Row) -> some View {
        Group {
            if let at = row.at { Text(at, format: .dateTime.hour().minute()) } else { Text("—") }
        }
    }

    private func badge(_ result: AIUsageSummary.Result) -> StatusBadge {
        switch result {
        case .passed: StatusBadge(text: result.text, color: .green)
        case .failed: StatusBadge(text: result.text, color: .red)
        case .noCall: StatusBadge(text: result.text, color: .gray)
        }
    }

    // MARK: 불러오기

    private func loadList() async {
        guard let client = app.client, let projectID = app.selectedProjectID else { return }
        do {
            deployments = try await client.send(.deployments(projectID: projectID)).items
            if selectedID == nil || !deployments.contains(where: { $0.id == selectedID }) {
                selectedID = deployments.first?.id
            }
        } catch {
            app.handle(error)
            if detail.value == nil { detail = .failed(error.localizedDescription) }
        }
    }

    private func loadDetail() async {
        guard let client = app.client, let selectedID else { return }
        if detail.value?.id != selectedID { detail = .loading }
        do {
            detail = .loaded(try await client.send(.deployment(id: selectedID)))
        } catch {
            app.handle(error)
            if detail.value == nil { detail = .failed(error.localizedDescription) }
        }
    }
}
