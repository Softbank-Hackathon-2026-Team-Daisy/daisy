import SwiftUI

/// W-05b 배포를 중단했어요: 한 환경이 3번 모두 실패해서 멈춘 상태.
struct StoppedStage: View {
    let deployment: Deployment
    var onChange: () -> Void
    @Environment(AppModel.self) private var app
    @Environment(Router.self) private var router
    @Environment(Workspace.self) private var workspace
    @State private var toast: ToastMessage?
    @State private var working = false
    @State private var errorMessage: String?

    private var targets: [Deployment.Target] { deployment.targets ?? [] }
    private var failed: Deployment.Target? { targets.first { $0.stepState == .failed } }
    private var failedName: String { failed.map { workspace.name(of: $0.targetId) } ?? "한 환경" }

    var body: some View {
        FlowPage(step: 4, title: "배포를 중단했어요",
                 description: "\(failedName) 검증이 3번 모두 실패해서 배포를 멈췄어요. 다른 환경은 검증을 마친 상태예요.") {
            InlineAlert(.danger, "\(failedName) · 3회 시도 모두 실패", failed?.errorSummary)
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
                            let failedHere = target.stepState == .failed
                            ProgressLine(name: workspace.type(of: target.targetId),
                                         text: failedHere ? "\(target.attempt)회 실패 · 중단" : "검증 통과") {
                                failedHere ? StatusBadge(text: "실패", color: .red) : StatusBadge(text: "검증 통과", color: .green)
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
                if let failed {
                    // Q7 결정 전 가안이라 웹과 같이 "(가안)"을 붙여요
                    Button("\(failedName) 빼고 계속 (가안)") { Task { await exclude(failed.targetId) } }
                        .buttonStyle(.glassCapsule)
                        .disabled(working || app.isViewer || targets.count < 2)
                }
            }
        }
        .toast($toast)
        .onAppear {
            toast = ToastMessage(kind: .danger, title: "\(failedName) 검증 실패 · 배포 중단",
                                 message: "오류 로그와 AI 수정 이력을 확인해 주세요")
        }
    }

    private func retry() async {
        guard let client = app.client else { return }
        working = true
        defer { working = false }
        do {
            _ = try await client.send(.retryDeployment(deploymentID: deployment.id))
            onChange()
        } catch {
            app.handle(error)
            errorMessage = error.localizedDescription
        }
    }

    private func exclude(_ targetID: String) async {
        guard let client = app.client else { return }
        working = true
        defer { working = false }
        do {
            _ = try await client.send(.excludeTarget(deploymentID: deployment.id, targetID: targetID))
            onChange()
        } catch {
            app.handle(error)
            errorMessage = error.localizedDescription
        }
    }
}
