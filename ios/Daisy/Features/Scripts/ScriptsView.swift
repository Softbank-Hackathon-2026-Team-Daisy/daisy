import SwiftUI

/// W-11 스크립트: AI가 만들고 검증을 통과한 Terraform. 같은 환경에 다시 배포할 땐 이미지 태그만 바꿔 재사용해요.
struct ScriptsView: View {
    @Environment(AppModel.self) private var app
    @Environment(Workspace.self) private var workspace
    @State private var scripts: LoadState<[Script]> = .idle
    @State private var selectedID: String?
    @State private var tabTarget: String?

    var body: some View {
        PageScaffold(.app("스크립트"),
                     subtitle: .app("AI가 만들고 검증을 통과한 Terraform이에요. 같은 환경에 다시 배포할 땐 이미지 태그만 바꿔 재사용해서 AI를 부르지 않아요.")) {
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
                            SectionCard(.app("검증된 스크립트")) {
                                if scripts.isEmpty {
                                    ContentUnavailableView("아직 검증된 스크립트가 없어요", systemImage: "apple.terminal",
                                                           description: Text("첫 배포에서 AI가 만든 Terraform이 검증을 통과하면 여기에 쌓여요"))
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
                                        .equalCardHeights()
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
                    Text(reuseText(script)).font(.subheadline.monospacedDigit())
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
                        Text([checks(script), script.status == .verified ? script.reuseCount.map { String.app("재사용 \($0)회") } : nil].compactMap { $0 }.joined(separator: " · "))
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

    /// 웹: "AI 생성 · 시도 2/3 통과 (보안 그룹 수정)" / "재사용 · 시도 1/3 통과" / "AI 생성 · 3회 실패 → 폐기"
    private func origin(_ script: Script) -> String {
        // 폐기 = 원본 없음 · 보관 기한 지남 (서버 #68, "3회 실패"가 아니에요)
        if script.status == .discarded { return .app("\(howMade(script)) · 원본 보관 기한 지남 → 폐기") }
        let base = script.attempt.map { String.app("\(howMade(script)) · 시도 \($0)/3 통과") } ?? howMade(script)
        return script.note.map { "\(base) (\($0))" } ?? base
    }

    private func howMade(_ script: Script) -> String { script.origin == .reused ? String.app("재사용") : String.app("AI 생성") }

    /// 웹: 검증된 스크립트만 재사용 횟수, 나머지는 "—"
    private func reuseText(_ script: Script) -> String {
        script.status == .verified ? script.reuseCount.map { String.app("\($0)회") } ?? "—" : "—"
    }

    /// 웹: "validate · plan · 위험 0" / "plan 실패" (WR-10 `validation`)
    private func checks(_ script: Script) -> String {
        guard let v = script.validation else { return "—" }
        if v.validate == false { return .app("validate 실패") }
        // `plan: false`는 "아직 plan 없음"이에요 (서버 #68)
        if v.plan == false { return .app("validate 통과 · plan 없음") }
        return .app("validate · plan · 위험 \(v.risks ?? 0)")
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
                CodeBlock(header: [file.path, howMade(script), script.attempt.map { String.app("시도 \($0)/3") }].compactMap { $0 }.joined(separator: " · "),
                          aiGenerated: script.origin != .reused, code: file.content)
            } else {
                // 목록(WR-10)에는 파일이 오지 않아요. 내용은 WR-07(배포별 스크립트)로만 받아요
                Text(script.status == .discarded ? "폐기된 스크립트는 내용을 보관하지 않아요." : "스크립트 내용은 아직 서버에서 받지 않아요 (WR-07).")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }

    private func info(_ script: Script) -> some View {
        SectionCard(.app("정보")) {
            InfoRow(.app("기준 이미지"), script.baseCommit.map { String($0.prefix(7)) }, monospaced: true)
            InfoRow(.app("입력"), script.input)
            InfoRow(.app("AI 토큰"), script.aiTokens.map { $0.appFormatted })
            InfoRow(String.app("저장 위치"), script.storage ?? String.app("[미정]"))
            InfoRow(.app("만든 시각"), script.createdAt.map { TimeText.dayClock($0) })
            if script.status == .verified {
                InlineAlert(.info, .app("다음 배포는 재사용"), .app("이미지 태그만 바꿔서 AI 호출 0회로 배포해요."))
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
