import SwiftUI

/// 3 배포 상세 (A-04, 서버 D2 제공). D2는 5초 폴링, D3에 SSE로 바꿔요.
struct DeploymentDetailView: View {
    @Environment(AppModel.self) private var app
    @State private var store: DeploymentDetailStore

    init(deploymentID: String) {
        _store = State(initialValue: DeploymentDetailStore(deploymentID: deploymentID))
    }

    var body: some View {
        LoadStateView(state: store.deployment, retry: { await store.refresh(using: app) }) { deployment in
            List {
                Section {
                    LabeledContent("상태") { deployment.state.badge }
                    LabeledContent("커밋") { CommitLabel(commit: deployment.commit) }
                    if let createdBy = deployment.createdBy {
                        LabeledContent("시작한 사람", value: createdBy)
                    }
                    if deployment.pendingApproval != nil {
                        NavigationLink("plan 승인하러 가기") {
                            PlanApprovalView(deploymentID: deployment.id)
                        }
                        .foregroundStyle(.orange)
                    }
                }
                Section("환경별 진행") {
                    ForEach(deployment.targets ?? []) { TargetProgressRow(target: $0) }
                }
            }
            .refreshable { await store.refresh(using: app) }
        }
        .navigationTitle("배포 상세")
        .task {
            await poll {
                guard !store.isFinished else { return }
                await store.refresh(using: app)
            }
        }
    }
}

struct TargetProgressRow: View {
    let target: Deployment.Target

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(target.targetId).font(.headline)
                Spacer()
                Text(target.attemptText).font(.caption).foregroundStyle(.secondary)
            }
            HStack(spacing: 6) {
                Circle().fill(target.stepState.color).frame(width: 8, height: 8)
                Text(target.step.displayName).font(.subheadline)
                if target.reusedScript == true {
                    StatusBadge(text: "재사용 · AI 0회", color: .teal)
                }
            }
            if let error = target.errorSummary {
                Text(error).font(.caption).foregroundStyle(.red)
            }
            if let url = target.url {
                Link(url.absoluteString, destination: url).font(.caption)
            }
        }
    }
}
