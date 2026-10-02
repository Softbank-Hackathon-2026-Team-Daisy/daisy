import SwiftUI

/// W-05b: 한 환경이 apply 전에 3번 모두 실패한 배포. 실패한 환경만 멈추고 나머지는 계속 가요 (Q7, 9/30 와이어프레임 수정).
/// 버튼은 웹과 같이 "오류 로그 보기"(W-11 스크립트) · "○○만 다시 시도"(실패한 환경 전부) · 승인할 환경이 남으면 "나머지 환경 plan 확인하기".
/// 문구 규칙은 `FlowCopy.stopped`, 환경별 한 줄은 `generateRow`.
struct StoppedStage: View {
    let deployment: Deployment
    @Environment(AppModel.self) private var app
    @Environment(Router.self) private var router
    @Environment(Workspace.self) private var workspace
    @State private var toast: ToastMessage?
    @State private var working = false
    @State private var errorMessage: String?

    private var targets: [Deployment.Target] { deployment.targets ?? [] }
    private var failed: [Deployment.Target] { targets.filter(\.isFailed) }
    private var copy: FlowCopy.Stopped { FlowCopy.stopped(deployment, name: workspace.name(of:)) }
    private var failedNames: String { FlowCopy.join(failed.map { workspace.name(of: $0.targetId) }) }
    private var approvable: Bool {
        !targets.contains { [.waiting, .generating, .validating].contains($0.resolvedState) }
            && targets.contains { $0.resolvedState == .awaitingApproval }
    }

    var body: some View {
        FlowPage(step: 4, title: copy.title, description: copy.description) {
            ForEach(failed) { target in
                InlineAlert(.danger, .app("\(workspace.name(of: target.targetId)) · \(target.attempt)회 시도 모두 실패"), target.errorSummary)
            }
            AdaptiveGrid(minimumWidth: 320) {
                ForEach(failed) { target in
                    SectionCard(.app("\(workspace.name(of: target.targetId)) 시도 기록")) {
                        ForEach(target.generateSteps, id: \.self) { StepItemRow($0) }
                    }
                }
                SectionCard(.app("환경별 상태")) {
                    VStack(spacing: 10) {
                        ForEach(targets) { target in
                            let row = target.generateRow
                            ProgressLine(name: workspace.type(of: target.targetId), text: row.note) { row.badge }
                        }
                    }
                }
            }
            if let errorMessage { InlineAlert(.danger, .app("다시 시도하지 못했어요"), errorMessage) }
            FlowButtons {
                Button("오류 로그 보기") { router.tab = .scripts }
                    .buttonStyle(.glassCapsule)
                Button("\(failedNames)만 다시 시도") { Task { await retry() } }
                    .buttonStyle(.glassCapsule)
                    .disabled(working || app.isViewer || failed.isEmpty)
                if approvable {
                    Button("나머지 환경 plan 확인하기") { router.push(.plan(deployment.id)) }
                        .buttonStyle(.glassCapsule)
                }
            }
        }
        .toast($toast)
        .task(id: failed.map(\.targetId)) {
            toast = ToastMessage(kind: .danger, title: copy.toastTitle, message: .app("오류 로그와 AI 수정 이력을 확인해 주세요"))
        }
    }

    /// 실패한 환경만 원본 배포에서 다시 시도해요 (`POST /deployments/{id}/retry`, `RetryRequest`). 새 배포의 시도는 1/3부터예요 (10/1 서버)
    private func retry() async {
        guard let client = app.client else { return }
        working = true
        defer { working = false }
        do {
            let next = try await client.send(.retry(.failed(of: deployment)))
            router.push(.started(next.id))
        } catch {
            app.handle(error)
            errorMessage = error.localizedDescription
        }
    }
}
