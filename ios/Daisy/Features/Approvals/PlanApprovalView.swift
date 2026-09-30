import SwiftUI

/// plan 요약을 보고 승인 · 거절해요. 리소스 전체 목록은 웹에서 봐요 (SPEC §1-1).
struct PlanApprovalView: View {
    @Environment(AppModel.self) private var app
    @State private var store: PlanApprovalStore

    init(deploymentID: String) {
        _store = State(initialValue: PlanApprovalStore(deploymentID: deploymentID))
    }

    var body: some View {
        LoadStateView(state: store.plan, retry: { await store.load(using: app) }) { plan in
            Form {
                ForEach(plan.targets) { target in
                    Section(target.targetId) {
                        LabeledContent("생성 · 변경 · 삭제") {
                            Text("\(target.counts.create) · \(target.counts.update) · \(target.counts.delete)")
                                .monospacedDigit()
                        }
                        if target.hasDelete {
                            Label("삭제되는 리소스가 있어요", systemImage: "trash")
                                .foregroundStyle(.red)
                        }
                        ForEach(target.risks, id: \.self) { risk in
                            Label {
                                VStack(alignment: .leading) {
                                    Text(risk.message)
                                    if let resource = risk.resource {
                                        Text(resource).font(.caption.monospaced()).foregroundStyle(.secondary)
                                    }
                                }
                            } icon: {
                                Image(systemName: "exclamationmark.shield").foregroundStyle(risk.level.color)
                            }
                        }
                    }
                }
                if let cost = plan.aiUsage?.costText {
                    Section("AI 비용") { Text(cost) }
                }
                decisionSection(plan)
            }
        }
        .navigationTitle("plan 승인")
        .task { await store.load(using: app) }
    }

    @ViewBuilder
    private func decisionSection(_ plan: Plan) -> some View {
        Section {
            if app.isViewer {
                Text("읽기 전용 계정이라 승인할 수 없어요.").foregroundStyle(.secondary)
            } else {
                if plan.hasDelete {
                    // (가칭) confirm_text에 넣을 값은 서버 확정 대기 (SPEC §6-4)
                    TextField("삭제를 확인하려면 입력해 주세요", text: $store.confirmText)
                }
                Button("승인") { Task { await store.submit(.approve, using: app) } }
                    .disabled(store.isSubmitting || (plan.hasDelete && store.confirmText.isEmpty))
                Button("거절", role: .destructive) { Task { await store.submit(.reject, using: app) } }
                    .disabled(store.isSubmitting)
            }
            if let result = store.result {
                Text(result).font(.callout)
            }
        }
    }
}
