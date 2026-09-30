import SwiftUI

/// W-11 스크립트: AI가 만들고 검증을 통과한 Terraform. 같은 환경에 다시 배포할 땐 이미지 태그만 바꿔 재사용해요.
struct ScriptsView: View {
    @Environment(AppModel.self) private var app
    @Environment(Workspace.self) private var workspace
    @State private var scripts: LoadState<[Script]> = .idle
    @State private var selectedID: String?
    @State private var tabTarget: String?

    var body: some View {
        PageScaffold("스크립트",
                     subtitle: "AI가 만들고 검증을 통과한 Terraform이에요. 같은 환경에 다시 배포할 땐 이미지 태그만 바꿔 재사용해서 AI를 부르지 않아요.") {
            Button { Task { await load() } } label: { Label("새로 고침", systemImage: "arrow.clockwise") }
                .buttonStyle(.glassCircle)
                .help("새로 고침")
        } content: {
            if app.selectedProjectID == nil {
                NoProjectView()
            } else {
                LoadStateView(state: scripts, retry: { await load() }) { scripts in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            SectionCard("검증된 스크립트") {
                                if scripts.isEmpty {
                                    Text("아직 검증된 스크립트가 없어요").foregroundStyle(.secondary)
                                } else {
                                    ViewThatFits(in: .horizontal) {
                                        table(scripts).frame(minWidth: 720)
                                        list(scripts)
                                    }
                                }
                            }
                            if let script = selected(scripts) {
                                ViewThatFits(in: .horizontal) {
                                    HStack(alignment: .top, spacing: 16) { code(script, all: scripts); info(script).frame(width: 320) }
                                    VStack(spacing: 16) { code(script, all: scripts); info(script) }
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

    private func selected(_ scripts: [Script]) -> Script? {
        if let tabTarget {
            return scripts.filter { $0.targetId == tabTarget && $0.status == .verified }.first
                ?? scripts.first { $0.targetId == tabTarget }
        }
        return scripts.first { $0.id == selectedID } ?? scripts.first
    }

    // MARK: 표

    /// 웹 열: 환경 · 버전 · 만든 방식 · 검증 · 재사용 · 마지막 사용
    private func table(_ scripts: [Script]) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 12) {
            GridRow { Text("환경"); Text("버전"); Text("만든 방식"); Text("검증"); Text("재사용"); Text("마지막 사용") }
                .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Divider()
            ForEach(scripts) { script in
                GridRow {
                    EnvTag(type: workspace.type(of: script.targetId))
                    Text(script.version).font(.subheadline.monospaced())
                    Text(origin(script)).font(.subheadline)
                    Text(checks(script)).font(.caption).foregroundStyle(script.status == .discarded ? .red : .secondary)
                    Text(script.reuseCount.map { "\($0)회" } ?? "—").font(.subheadline.monospacedDigit())
                    lastUsed(script).font(.caption).foregroundStyle(.secondary)
                }
                .contentShape(.rect)
                .onTapGesture { selectedID = script.id; tabTarget = nil }
                .background(script.id == selectedID ? AnyShapeStyle(.fill.tertiary) : AnyShapeStyle(.clear))
            }
        }
    }

    private func list(_ scripts: [Script]) -> some View {
        VStack(spacing: 0) {
            ForEach(scripts) { script in
                Button { selectedID = script.id; tabTarget = nil } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack { EnvTag(type: workspace.type(of: script.targetId)); Text(script.version).font(.subheadline.monospaced()); Spacer(); lastUsed(script).font(.caption).foregroundStyle(.secondary) }
                        Text(origin(script)).font(.subheadline)
                        Text([checks(script), script.reuseCount.map { "재사용 \($0)회" }].compactMap { $0 }.joined(separator: " · "))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                if script.id != scripts.last?.id { Divider() }
            }
        }
    }

    /// 웹: "AI 생성 · 시도 2/3 통과 (보안 그룹 수정)" / "AI 생성 · 3회 실패 → 폐기"
    private func origin(_ script: Script) -> String {
        let base = switch (script.status, script.origin) {
        case (.discarded, _): "AI 생성 · \(script.attempt)회 실패 → 폐기"
        case (_, .reused): "재사용 · 이미지 태그만 교체"
        default: "AI 생성 · 시도 \(script.attempt)/3 통과"
        }
        return script.note.map { "\(base) (\($0))" } ?? base
    }

    /// 웹: "validate · plan · 위험 0" / "plan 실패" (WR-10 `validation`)
    private func checks(_ script: Script) -> String {
        guard let v = script.validation else { return "—" }
        if v.validate == false { return "validate 실패" }
        if v.plan == false { return "plan 실패" }
        return "validate · plan · 위험 \(v.risks ?? 0)"
    }

    private func lastUsed(_ script: Script) -> some View {
        Group {
            if let date = script.lastUsedAt { RelativeTime(date: date) } else { Text("—") }
        }
    }

    // MARK: 코드 · 정보

    private func code(_ script: Script, all: [Script]) -> some View {
        let file = script.files?.first
        return SectionCard("\(file?.path ?? "main.tf") · \(script.version)") {
            let targetIDs = Array(Set(all.map(\.targetId))).sorted()
            if targetIDs.count > 1 {
                GlassSegmented(selection: Binding(get: { script.targetId }, set: { tabTarget = $0 }),
                               items: targetIDs.map { id in
                                   .init(value: id, title: workspace.name(of: id))
                               })
            }
            if let file {
                CodeBlock(header: "\(file.path) · AI 생성 · 시도 \(script.attempt)/3",
                          aiGenerated: script.origin == .aiGenerated, code: file.content)
            } else {
                Text("스크립트 내용은 배포 화면(W-05)에서 볼 수 있어요").font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }

    private func info(_ script: Script) -> some View {
        SectionCard("정보") {
            InfoRow("기준 이미지", script.baseCommit.map { String($0.prefix(7)) }, monospaced: true)
            InfoRow("입력", script.input)
            InfoRow("AI 토큰", script.aiTokens.map { $0.formatted() })
            InfoRow("저장 위치", script.storage)
            InfoRow("만든 시각", script.createdAt.map { $0.formatted(date: .numeric, time: .shortened) })
            if script.status == .verified {
                InlineAlert(.info, "다음 배포는 재사용", "이미지 태그만 바꿔서 AI 호출 0회로 배포해요.")
            }
        }
    }

    private func load() async {
        guard let client = app.client, let projectID = app.selectedProjectID else { return }
        if scripts.value == nil { scripts = .loading }
        do {
            scripts = .loaded(try await client.send(.scripts(projectID: projectID)).items)
        } catch {
            app.handle(error)
            if scripts.value == nil { scripts = .failed(error.localizedDescription) }
        }
    }
}
