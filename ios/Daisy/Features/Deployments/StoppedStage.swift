import SwiftUI

/// W-05b 배포를 중단했어요: apply 전에 모든 환경이 멈춘 배포.
/// Q7(9/29 서버 결정): 3회는 환경별이고, 한 환경이 실패해도 나머지는 계속 가요. 그래서 "○○ 빼고 계속" 버튼은 없어요.
struct StoppedStage: View {
    let deployment: Deployment
    @Environment(AppModel.self) private var app
    @Environment(Router.self) private var router
    @Environment(Workspace.self) private var workspace
    @State private var toast: ToastMessage?
    @State private var working = false
    @State private var errorMessage: String?

    private var targets: [Deployment.Target] { deployment.targets ?? [] }
    private var failed: Deployment.Target? { targets.first(where: \.isFailed) }
    private var failedName: String { failed.map { workspace.name(of: $0.targetId) } ?? "한 환경" }

    var body: some View {
        FlowPage(step: 4, title: "배포를 중단했어요",
                 description: "\(failedName) 검증이 \(failed?.attempt ?? 3)번 모두 실패해서 배포를 멈췄어요.") {
            InlineAlert(.danger, "\(failedName) · \(failed?.attempt ?? 3)회 시도 모두 실패", failed?.errorSummary)
            AdaptiveGrid(minimumWidth: 320) {
                SectionCard("\(failedName) 시도 기록") {
                    let steps = failed?.steps ?? []
                    if steps.isEmpty {
                        Text("시도 기록을 불러오지 못했어요").foregroundStyle(.secondary)
                    }
                    ForEach(steps, id: \.self) { StepItemRow($0) }
                }
                SectionCard("환경별 상태") {
                    VStack(spacing: 10) {
                        ForEach(targets) { target in
                            ProgressLine(name: workspace.type(of: target.targetId),
                                         text: target.isFailed ? "\(target.attempt)회 실패 · 중단" : "검증 통과") {
                                target.isFailed ? StatusBadge(text: "실패", color: .red) : StatusBadge(text: "검증 통과", color: .green)
                            }
                        }
                    }
                }
            }
            if let errorMessage { InlineAlert(.danger, "요청하지 못했어요", errorMessage) }
            FlowButtons {
                Button("오류 로그 보기") { router.push(.logs(deploymentID: deployment.id, targetID: failed?.targetId)) }
                    .buttonStyle(.glassCapsule)
                Button("처음부터 다시 시도") { Task { await retry() } }
                    .buttonStyle(.glassCapsule)
                    .disabled(working || app.isViewer)
            }
        }
        .toast($toast)
        .onAppear {
            toast = ToastMessage(kind: .danger, title: "\(failedName) 검증 실패 · 배포 중단",
                                 message: "오류 로그와 AI 수정 이력을 확인해 주세요")
        }
    }

    /// 같은 커밋 · 같은 환경으로 새 배포를 만들어요 (WR-05). 별도 재시도 API는 쓰지 않아요.
    private func retry() async {
        guard let client = app.client else { return }
        working = true
        defer { working = false }
        do {
            let next = try await client.send(.startDeployment(projectID: deployment.projectId, commit: deployment.commit,
                                                              targetIDs: targets.map(\.targetId)))
            router.replaceTop(with: .started(next.id))
        } catch {
            app.handle(error)
            errorMessage = error.localizedDescription
        }
    }
}
