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
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    summary(deployment).cardStyle()
                    Text("환경별 진행").font(.headline)
                    // 폰은 세로로, iPad · Mac은 환경이 나란히 보여서 병렬 배포가 한눈에 보여요.
                    AdaptiveGrid(minimumWidth: 260) {
                        ForEach(deployment.targets ?? []) { TargetProgressCard(target: $0) }
                    }
                }
                .padding()
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

extension DeploymentDetailView {
    private func summary(_ deployment: Deployment) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            LabeledContent("상태") { deployment.state.badge }
            LabeledContent("커밋") { CommitLabel(commit: deployment.commit) }
            if let createdBy = deployment.createdBy {
                LabeledContent("시작한 사람", value: createdBy)
            }
            if deployment.pendingApproval != nil {
                NavigationLink {
                    PlanApprovalView(deploymentID: deployment.id)
                } label: {
                    Label("변경 사항 확인 후 승인", systemImage: "checkmark.seal")
                }
                .foregroundStyle(.orange)
            }
        }
    }
}

struct TargetProgressCard: View {
    let target: Deployment.Target

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(target.targetId).font(.headline)
                Spacer()
                if target.reusedScript == true {
                    StatusBadge(text: "AI 0회", color: .teal)
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Circle().fill(target.stepState.color).frame(width: 8, height: 8)
                Text(target.progressText).font(.subheadline)
            }
            if let error = target.errorSummary {
                Text(error).font(.caption).foregroundStyle(.red)
            }
            if let url = target.url {
                Link(url.absoluteString, destination: url).font(.caption)
            }
        }
        .cardStyle()
    }
}
