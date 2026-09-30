import SwiftUI

/// W-05 인프라 코드 생성 · 검증: 환경별 진행 · 환경 탭 · 검증 단계 · 생성된 스크립트.
/// 다음 버튼은 없어요. 통과하면 승인(W-06)으로 서버가 넘겨요. 한 환경이 3회 실패하면 W-05b로 바뀌어요 (`RunStage`).
struct GenerateStage: View {
    let deployment: Deployment
    @Environment(AppModel.self) private var app
    @Environment(Workspace.self) private var workspace
    @State private var selectedTarget: String?
    @State private var script: Script?

    private var targets: [Deployment.Target] { deployment.targets ?? [] }
    private var current: Deployment.Target? {
        targets.first { $0.targetId == (selectedTarget ?? targets.first?.targetId) }
    }

    var body: some View {
        FlowPage(step: 4, title: "인프라 코드 생성 · 검증",
                 description: "AI가 환경별 Terraform을 만들고 validate · plan · 위험 설정 검사를 통과할 때까지 최대 3번 고쳐요.") {
            SectionCard("환경별 진행") {
                VStack(spacing: 10) {
                    ForEach(targets) { target in
                        ProgressLine(name: workspace.type(of: target.targetId), text: target.progressText) {
                            validationBadge(target)
                        }
                    }
                }
            }
            EnvironmentTabs(selection: $selectedTarget, targetIDs: targets.map(\.targetId))
            if let current {
                AdaptiveGrid(minimumWidth: 320) {
                    SectionCard("\(workspace.name(of: current.targetId)) 검증 단계") {
                        ForEach(current.steps ?? [], id: \.self) { StepItemRow($0) }
                        if (current.steps ?? []).isEmpty {
                            StepItemRow(name: current.step.displayName, state: current.stepState)
                        }
                        if current.stepState == .failed, let error = current.errorSummary {
                            InlineAlert(.danger,
                                        current.step == .riskCheck ? "위험 설정 발견 · AI가 수정 중" : "\(current.step.displayName) 실패 · AI가 수정 중",
                                        error)
                        }
                    }
                    SectionCard("생성된 스크립트") {
                        if let script, let file = script.files?.first {
                            CodeBlock(header: scriptHeader(file.path, attempt: current.attempt),
                                      aiGenerated: current.reusedScript != true, code: file.content)
                        } else {
                            Text("스크립트를 만들고 있어요").foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .task(id: "\(current?.targetId ?? "")-\(current?.attempt ?? 0)") { await loadScript() }
    }

    /// 웹: 검증 통과 · 검증 중 · 실패
    private func validationBadge(_ target: Deployment.Target) -> StatusBadge {
        if target.isFailed { return StatusBadge(text: "실패", color: .red) }
        if target.state == .awaitingApproval { return StatusBadge(text: "검증 통과", color: .green) }
        if [.plan, .riskCheck].contains(target.step) && target.stepState == .done {
            return StatusBadge(text: "검증 통과", color: .green)
        }
        return StatusBadge(text: "검증 중", color: .blue)
    }

    /// 웹: "aws/main.tf · AI 수정 2회차" / "aws/main.tf · AI 생성"
    private func scriptHeader(_ file: String, attempt: Int) -> String {
        return attempt > 1 ? "\(file) · AI 수정 \(attempt - 1)회차" : "\(file) · AI 생성"
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
