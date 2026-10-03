import SwiftUI

/// W-12 AI 사용량 — 기본은 이 프로젝트 전체(배포마다 A-05 합계를 더해요, 10/3 앱 추가), 배포를 하나 고르면 그 배포의 합계(A-05 plan)와 호출 기록(`ai-usage?deployment_id=`)을 봐요.
/// 재사용으로 AI를 안 부른 환경은 호출 기록이 없어서 "— 검증된 스크립트 재사용" 한 줄로 보여줘요. 규칙은 `AIUsageSummary`.
struct AIUsageView: View {
    @Environment(AppModel.self) private var app
    @Environment(Workspace.self) private var workspace
    @State private var store = AIUsageStore()
    /// nil이면 전체 사용량
    @State private var selectedID: String?
    @State private var pickerExpanded = false

    /// 프로젝트나 고른 배포가 바뀌면 폴링을 새로 시작해요. 이전 배포 요청은 취소되고 늦게 와도 버려져요 (AI3)
    private struct TaskKey: Hashable {
        let projectID: String?
        let selectedID: String?
    }

    private var deployments: [Deployment] { store.list.value(for: app.selectedProjectID) ?? [] }

    var body: some View {
        PageScaffold(.app("AI 사용량"),
                     subtitle: .app("배포마다 AI를 몇 번, 얼마나 썼는지 봐요. 판단이 필요한 생성 · 수정에만 AI를 쓰고, 검증된 스크립트는 재사용해요.")) {
            deploymentPicker
            Button { Task { await refresh() } } label: { Label("새로 고침", systemImage: "arrow.clockwise") }
                .buttonStyle(.glassCircle)
                .help("새로 고침")
        } content: {
            if let projectID = app.selectedProjectID {
                // 배포 목록이 기준이에요. 처음부터 못 받으면 오류를 보여줘요 ("0회"로 가리지 않아요, AI2)
                LoadStateView(state: store.list.state(for: projectID), retry: { await refresh() }) { deployments in
                    if deployments.isEmpty {
                        ContentUnavailableView("아직 배포가 없어요", systemImage: "chart.bar",
                                               description: Text("배포하면 AI를 몇 번, 얼마나 썼는지 여기서 봐요"))
                            .emptyStateCentered()
                    } else if let selectedID {
                        LoadStateView(state: store.detail.state(for: AIUsageStore.detailScope(projectID: projectID, deploymentID: selectedID)),
                                      retry: { await refresh() }) { detail in
                            content(detail.summary)
                        }
                    } else {
                        LoadStateView(state: store.overall.state(for: projectID), retry: { await refresh() }) { totals in
                            totalsContent(totals)
                        }
                    }
                }
            } else {
                NoProjectView()
            }
        }
        // 프로젝트 · 배포 이벤트(앱 복귀 · 전환 포함)가 오면 바로, 아니면 SSE 15초 · 5초 (AI1). 한 번에 합계는 한 번만 (AI4)
        .task(id: TaskKey(projectID: app.selectedProjectID, selectedID: selectedID)) {
            await poll(on: workspace.live.changes, every: { PollInterval.seconds(live: workspace.live.isLive) }) {
                await refresh()
            }
        }
        // 이전 프로젝트에서 고른 배포는 새 프로젝트에 없어요
        .onChange(of: app.selectedProjectID) { selectedID = nil }
    }

    private var staleBanner: some View {
        StaleBanner(since: store.staleSince(projectID: app.selectedProjectID, selectedID: selectedID))
    }

    // MARK: 배포 고르기 (웹 Select "dep_42 · a1b2c3d · 21:10 배포")
    // 개요의 프로젝트 고르기와 같아요: 평소엔 원 버튼, 누르면 지금 고른 이름이 펼쳐지고, 한 번 더 누르면 목록 (10/3)

    private var selectedTitle: String {
        guard let selectedID else { return .app("전체 사용량") }
        return deployments.first { $0.id == selectedID }.map { AIUsageSummary.pickerTitle($0) } ?? .app("배포 선택")
    }

    private var deploymentPicker: some View {
        ExpandingMenuButton(systemImage: "wonsign.circle", title: selectedTitle, isExpanded: $pickerExpanded,
                            options: [ExpandingMenuOption(id: "all", title: .app("전체 사용량"),
                                                          isSelected: selectedID == nil) { select(nil) }]
                                + deployments.enumerated().map { index, deployment in
                                    ExpandingMenuOption(id: deployment.id, title: AIUsageSummary.pickerTitle(deployment),
                                                        isSelected: deployment.id == selectedID, separated: index == 0) { select(deployment.id) }
                                })
        .disabled(deployments.isEmpty)
    }

    private func select(_ id: String?) {
        selectedID = id
    }

    // MARK: 전체 사용량

    private func totalsContent(_ totals: AIUsageTotals) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                staleBanner
                AdaptiveGrid(minimumWidth: 150, fillsWidth: true) {
                    tile(.app("AI 호출"), .app("\(totals.calls)회"), .app("배포 \(totals.rows.count)건 중 \(totals.deploymentsWithCalls)건"))
                    tile(.app("토큰"), totals.tokens.map { $0.appFormatted } ?? "—",
                         totals.isPartial ? .app("확인한 호출만 더했어요") : .app("입력 + 출력"))
                    tile(.app("비용"), totals.costKrw.map { "₩\($0.appFormatted)" } ?? "—", totalCostNote(totals))
                    tile(.app("재사용한 환경"), .app("\(totals.reusedTargets)곳"), .app("AI 호출 0회"))
                }
                SectionCard(.app("배포별 사용량"), subtitle: .app("배포를 누르면 호출 기록을 봐요")) {
                    VStack(spacing: 0) {
                        ForEach(totals.rows) { row in
                            Button { select(row.deployment.id) } label: { totalsRow(row) }
                                .buttonStyle(.plain)
                            if row.id != totals.rows.last?.id { Divider() }
                        }
                    }
                }
            }
            .padding(20)
        }
        .refreshable { await refresh() }
    }

    private func totalsRow(_ row: AIUsageTotals.Row) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(AIUsageSummary.pickerTitle(row.deployment)).font(.subheadline).lineLimit(1)
                Text([String.app("AI 호출 \(row.calls)회"),
                      row.tokens.map { String.app("토큰 \($0.appFormatted)") },
                      row.reusedTargets > 0 ? String.app("재사용 \(row.reusedTargets)곳") : nil]
                    .compactMap { $0 }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Text(row.costKrw.map { "₩\($0.appFormatted)" } ?? "—").font(.subheadline.monospacedDigit())
            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 10)
        .contentShape(.rect)
    }

    private func totalCostNote(_ totals: AIUsageTotals) -> String {
        ([String.app("추정")] + [totals.exchangeRate.map { String.app("환율 \(Int($0).appFormatted)원") },
                                 totals.isPartial ? String.app("일부 확인 못 함") : nil].compactMap { $0 }).joined(separator: " · ")
    }

    // MARK: 내용

    private func content(_ summary: AIUsageSummary) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                staleBanner
                // iPhone 폭에서도 2×2로 보이게 최소 폭을 150으로
                AdaptiveGrid(minimumWidth: 150, fillsWidth: true) {
                    tile(.app("AI 호출"), .app("\(summary.calls)회"), .app("이번 배포"))
                    tile(.app("토큰"), summary.tokens.map { $0.appFormatted } ?? "—", .app("입력 + 출력"))
                    tile(.app("비용"), summary.costKrw.map { "₩\($0.appFormatted)" } ?? "—", costNote(summary))
                    tile(.app("재사용한 환경"), .app("\(summary.reusedTargetIDs.count)곳"), reuseNote(summary))
                }
                SectionCard(.app("이 배포의 호출 기록")) {
                    if summary.rows.isEmpty {
                        // 빈 목록은 "AI를 안 썼다"는 뜻이 아니에요 (서버 #60): 기록이 아직 안 왔을 수 있어요
                        Text("호출 기록을 아직 받지 않았어요 — AI를 안 썼다는 뜻은 아니에요").foregroundStyle(.secondary)
                    } else {
                        ViewThatFits(in: .horizontal) {
                            table(summary.rows).frame(minWidth: 720)
                            list(summary.rows)
                        }
                    }
                }
                InlineAlert(.info, .app("PoC N-09 (선택)"), .app("비용 표시는 N-09 결과에 따라 달라져요. 범위에서 빠지면 호출 수 · 토큰만 보여줘요."))
            }
            .padding(20)
        }
        .refreshable { await refresh() }
    }

    /// 비용은 추정치예요. 서버가 적용한 환율을 같이 보여줘요. 웹: "추정 · 환율 1,380원 · LLM Claude"
    private func costNote(_ summary: AIUsageSummary) -> String {
        // LLM은 Claude로 확정 (9/30 김승환 담당 결정)
        ([String.app("추정")] + [summary.exchangeRate.map { String.app("환율 \(Int($0).appFormatted)원") }, "LLM Claude"].compactMap { $0 }).joined(separator: " · ")
    }

    /// 웹: "온프레미스 · AI 호출 0회"
    private func reuseNote(_ summary: AIUsageSummary) -> String {
        guard !summary.reusedTargetIDs.isEmpty else { return .app("없음") }
        return .app("\(FlowCopy.join(summary.reusedTargetIDs.map { workspace.name(of: $0) })) · AI 호출 0회")
    }

    private func tile(_ label: String, _ value: String, _ note: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title.weight(.semibold).monospacedDigit())
                .lineLimit(1).minimumScaleFactor(0.5)
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
                    Text(row.tokens.map { $0.appFormatted } ?? "—").font(.subheadline.monospacedDigit())
                    Text(row.costKrw.map { "₩\($0.appFormatted)" } ?? "—").font(.subheadline.monospacedDigit())
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
                    Text([String.app("시도 \(row.attempt)"), row.tokens.map { String.app("토큰 \($0.appFormatted)") }, row.costKrw.map { "₩\($0.appFormatted)" }]
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
            if let at = row.at { Text(TimeText.clock(at)) } else { Text("—") }
        }
    }

    private func badge(_ result: AIUsageSummary.Result) -> StatusBadge {
        switch result {
        case .passed: StatusBadge(text: result.text, color: .green)
        case .failed: StatusBadge(text: result.text, color: .red)
        case .noCall, .unknown: StatusBadge(text: result.text, color: .gray)
        }
    }

    // MARK: 불러오기

    private func refresh() async {
        guard let projectID = app.selectedProjectID else { return }
        let selected = selectedID
        // 고른 배포가 목록에서 사라지면 전체로 돌아가요 (`.task(id:)`가 다시 시작해서 합계를 한 번 받아요)
        let stillListed = await store.refresh(using: app, projectID: projectID, selectedID: selected)
        if !stillListed, selectedID == selected {
            selectedID = nil
        }
    }
}
