import SwiftUI

/// W-05b: 한 환경이 apply 전에 3번 모두 실패한 배포. 실패한 환경만 멈추고 나머지는 계속 가요 (Q7, 9/30 와이어프레임 수정).
/// 버튼은 "오류 로그 보기"와 "○○만 다시 시도". 문구 규칙은 `FlowCopy.stopped`.
struct StoppedStage: View {
    let deployment: Deployment
    @Environment(AppModel.self) private var app
    @Environment(Router.self) private var router
    @Environment(Workspace.self) private var workspace
    @State private var toast: ToastMessage?
    @State private var working: String?
    @State private var errorMessage: String?

    private var targets: [Deployment.Target] { deployment.targets ?? [] }
    private var failed: [Deployment.Target] { targets.filter(\.isFailed) }
    private var copy: FlowCopy.Stopped { FlowCopy.stopped(deployment, name: workspace.name(of:)) }

    var body: some View {
        FlowPage(step: 4, title: copy.title, description: copy.description) {
            ForEach(failed) { target in
                InlineAlert(.danger, "\(workspace.name(of: target.targetId)) · \(target.attempt)회 시도 모두 실패", target.errorSummary)
            }
            AdaptiveGrid(minimumWidth: 320) {
                ForEach(failed) { target in
                    SectionCard("\(workspace.name(of: target.targetId)) 시도 기록") {
                        let steps = target.steps ?? []
                        if steps.isEmpty {
                            Text("시도 기록을 불러오지 못했어요").foregroundStyle(.secondary)
                        }
                        ForEach(steps, id: \.self) { StepItemRow($0) }
                    }
                }
                SectionCard("환경별 상태") {
                    VStack(spacing: 10) {
                        ForEach(targets) { target in
                            ProgressLine(name: workspace.type(of: target.targetId), text: statusText(target)) {
                                statusBadge(target)
                            }
                        }
                    }
                }
            }
            if let errorMessage { InlineAlert(.danger, "요청하지 못했어요", errorMessage) }
            FlowButtons {
                Button("오류 로그 보기") { router.push(.logs(deploymentID: deployment.id, targetID: failed.first?.targetId)) }
                    .buttonStyle(.glassCapsule)
                ForEach(failed) { target in
                    Button("\(workspace.name(of: target.targetId))만 다시 시도") { Task { await retry(target) } }
                        .buttonStyle(.glassCapsule)
                        .disabled(working != nil || app.isViewer)
                }
            }
        }
        .toast($toast)
        .task(id: failed.map(\.targetId)) {
            toast = ToastMessage(kind: .danger, title: copy.toastTitle, message: "오류 로그와 AI 수정 이력을 확인해 주세요")
        }
    }

    private func statusText(_ target: Deployment.Target) -> String {
        if target.isFailed { return "\(target.attempt)회 실패 · 중단" }
        if target.state == .awaitingApproval || ([.plan, .riskCheck].contains(target.step) && target.stepState == .done) {
            return "검증 통과"
        }
        return target.progressText
    }

    private func statusBadge(_ target: Deployment.Target) -> StatusBadge {
        if target.isFailed { return StatusBadge(text: "실패", color: .red) }
        if statusText(target) == "검증 통과" { return StatusBadge(text: "검증 통과", color: .green) }
        return StatusBadge(text: "검증 중", color: .blue)
    }

    /// 실패한 환경만 같은 커밋으로 새 배포를 만들어요 (WR-05, `RetryRequest`)
    private func retry(_ target: Deployment.Target) async {
        guard let client = app.client else { return }
        working = target.targetId
        defer { working = nil }
        let request = RetryRequest.only(target.targetId, of: deployment)
        do {
            let next = try await client.send(.startDeployment(projectID: request.projectID, commit: request.commit,
                                                              targetIDs: request.targetIDs))
            router.push(.started(next.id))
        } catch {
            app.handle(error)
            errorMessage = error.localizedDescription
        }
    }
}
