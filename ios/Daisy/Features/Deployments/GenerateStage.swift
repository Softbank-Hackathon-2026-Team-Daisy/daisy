import SwiftUI

/// W-05 인프라 코드 생성 · 검증: 환경별 진행 · 환경 탭 · 검증 단계 · 생성된 스크립트.
/// 검증이 끝나면 승인(W-06)으로 넘어가요. 모두 끝났는데 승인 대기가 남아 있으면 "변경 사항 확인하기"를 보여줘요 (웹과 같아요).
/// 한 환경이 3회 실패하면 W-05b로 바뀌어요 (`RunStage`). 한 줄 · 단계 규칙은 `Deployment.Target.generateRow` · `generateSteps`.
struct GenerateStage: View {
    let deployment: Deployment
    @Environment(AppModel.self) private var app
    @Environment(Router.self) private var router
    @Environment(Workspace.self) private var workspace
    @State private var selectedTarget: String?
    @State private var script: Script?

    private var targets: [Deployment.Target] { deployment.targets ?? [] }
    private static let busy: Set<TargetState> = [.waiting, .generating, .validating]

    /// 처음 여는 탭: 실패한 환경 → 진행 중인 환경 → 첫 환경 (웹과 같아요)
    private var defaultTarget: String? {
        (targets.first { $0.resolvedState == .failed }
            ?? targets.first { Self.busy.contains($0.resolvedState) }
            ?? targets.first)?.targetId
    }

    private var current: Deployment.Target? {
        targets.first { $0.targetId == (selectedTarget ?? defaultTarget) }
    }

    private var approvable: Bool {
        !targets.contains { Self.busy.contains($0.resolvedState) } && targets.contains { $0.resolvedState == .awaitingApproval }
    }

    var body: some View {
        FlowPage(step: 4, title: .app("인프라 코드 생성 · 검증"),
                 description: .app("AI가 환경별 Terraform을 만들고 validate · plan · 위험 설정 검사를 통과할 때까지 최대 3번 고쳐요.")) {
            SectionCard(.app("환경별 진행")) {
                VStack(spacing: 10) {
                    ForEach(targets) { target in
                        let row = target.generateRow
                        ProgressLine(name: workspace.type(of: target.targetId), text: row.note) { row.badge }
                    }
                }
            }
            EnvironmentTabs(selection: Binding(get: { selectedTarget ?? defaultTarget }, set: { selectedTarget = $0 }),
                            targetIDs: targets.map(\.targetId))
            if let current {
                AdaptiveGrid(minimumWidth: 320) {
                    SectionCard(.app("\(workspace.name(of: current.targetId)) 검증 단계")) {
                        ForEach(current.generateSteps, id: \.self) { StepItemRow($0) }
                        if let error = current.errorSummary {
                            InlineAlert(.danger,
                                        isFixing(current) ? String.app("위험 설정 발견 · AI가 수정 중") : String.app("검증 실패"),
                                        error)
                        }
                    }
                    SectionCard(.app("생성된 스크립트")) {
                        if let script, let file = script.files?.first {
                            CodeBlock(header: scriptHeader(file.path, target: current),
                                      aiGenerated: current.reusedScript != true, code: file.content)
                        } else {
                            ProgressView().frame(maxWidth: .infinity, minHeight: 120)
                        }
                    }
                }
            }
            if approvable {
                FlowButtons {
                    Button("변경 사항 확인하기") { router.push(.plan(deployment.id)) }
                        .buttonStyle(.glassCapsule)
                }
            }
        }
        .task(id: "\(current?.targetId ?? "")-\(current?.attempt ?? 0)") { await loadScript() }
    }

    /// 웹: "aws/main.tf · 검증된 스크립트 재사용" / "aws/main.tf · AI 수정 2회차" / "aws/main.tf · AI 생성"
    private func scriptHeader(_ file: String, target: Deployment.Target) -> String {
        if target.reusedScript == true { return .app("\(file) · 검증된 스크립트 재사용") }
        return target.attempt > 1 ? String.app("\(file) · AI 수정 \(target.attempt)회차") : String.app("\(file) · AI 생성")
    }

    /// 아직 검증 중인데 오류 요약이 있으면 AI가 고치는 중이에요 (`generateRow` 배지 "검증 중"과 같은 조건)
    private func isFixing(_ target: Deployment.Target) -> Bool {
        !target.isApprovedWaiting && [.validating, .unknown].contains(target.resolvedState)
    }

    private func loadScript() async {
        guard let client = app.client, let target = current else { return }
        script = try? await client.send(.deploymentScript(deploymentID: deployment.id, targetID: target.targetId))
    }
}

/// 환경 한 줄: 환경 태그 · 설명 · 배지 (웹 "환경별 진행" · "환경별 요약" · "환경별 상태")
struct ProgressLine<Badge: View>: View {
    let name: TargetType
    let text: String
    @ViewBuilder var badge: Badge

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                EnvTag(type: name)
                Text(text).font(.subheadline)
                Spacer(minLength: 8)
                badge
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack { EnvTag(type: name); Spacer(); badge }
                Text(text).font(.subheadline)
            }
        }
    }
}
