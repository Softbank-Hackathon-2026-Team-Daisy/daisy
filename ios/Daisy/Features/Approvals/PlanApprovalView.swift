import SwiftUI

/// W-06 변경 사항 확인 후 승인: 환경별 요약 · 환경 탭 · plan 리소스 · 아래 고정 승인 바.
struct PlanApprovalView: View {
    let deploymentID: String
    var deployment: Deployment?
    /// 승인하면 true, 거절하면 false. 없으면 배포 화면으로 바꿔 끼워요.
    var onDecision: ((Bool) -> Void)?
    @Environment(AppModel.self) private var app
    @Environment(Router.self) private var router
    @Environment(Workspace.self) private var workspace
    @State private var store: PlanApprovalStore
    @State private var selectedTarget: String?
    @State private var confirmingDelete = false

    init(deploymentID: String, deployment: Deployment? = nil, onDecision: ((Bool) -> Void)? = nil) {
        self.deploymentID = deploymentID
        self.deployment = deployment
        self.onDecision = onDecision
        _store = State(initialValue: PlanApprovalStore(deploymentID: deploymentID))
    }

    var body: some View {
        LoadStateView(state: store.plan, retry: { await store.load(using: app) }) { plan in
            FlowPage(step: 5, title: "변경 사항 확인 후 승인",
                     description: "환경별 plan 결과예요. 승인하면 선택한 모든 환경에 동시에 적용해요.") {
                summary(plan)
                EnvironmentTabs(selection: $selectedTarget, targetIDs: plan.targets.map(\.targetId))
                if let target = plan.targets.first(where: { $0.targetId == (selectedTarget ?? plan.targets.first?.targetId) }) {
                    planCard(target)
                }
                if let cost = plan.aiUsage?.costText {
                    Text("AI 비용 \(cost)").font(.caption).foregroundStyle(.secondary)
                }
            } bottom: {
                approvalBar(plan)
            }
        }
        .task { await store.load(using: app) }
        .onChange(of: store.decided) { _, decided in
            guard let decided else { return }
            if let onDecision {
                onDecision(decided == .approve)
            } else {
                router.replaceTop(with: .run(deploymentID))
            }
        }
        .alert("삭제되는 리소스가 있어요", isPresented: $confirmingDelete) {
            TextField("환경 이름", text: $store.confirmText)
            Button("취소", role: .cancel) { store.confirmText = "" }
            Button("승인하고 배포", role: .destructive) { Task { await store.submit(.approve, using: app) } }
        } message: {
            Text("확인을 위해 환경 이름을 입력해 주세요.")
        }
    }

    // MARK: 환경별 요약

    private func summary(_ plan: Plan) -> some View {
        SectionCard("환경별 요약") {
            VStack(spacing: 10) {
                ForEach(plan.targets) { target in
                    // 웹: "리소스 +6 ~0 −0 · 위험 설정 0건" / "리소스 +0 ~1 −0 · 이미지 태그만 교체"
                    let tail = target.reusedScript == true ? "이미지 태그만 교체" : "위험 설정 \(target.risks.count)건"
                    ProgressLine(name: workspace.type(of: target.targetId), text: "\(target.counts.summaryText) · \(tail)") {
                        StatusBadge(text: "검증 통과", color: .green)
                    }
                }
            }
        }
    }

    // MARK: 환경 plan

    private func planCard(_ target: Plan.Target) -> some View {
        SectionCard("\(workspace.name(of: target.targetId)) plan") {
            let resources = target.resources ?? []
            if resources.isEmpty {
                Text(target.counts.summaryText).font(.subheadline.monospacedDigit())
            }
            VStack(spacing: 4) {
                ForEach(resources, id: \.self) { ResourceDiffRow(resource: $0) }
            }
            if target.hasDelete {
                InlineAlert(.warning, "삭제되는 리소스가 있어요", "승인할 때 환경 이름을 한 번 더 확인해요.")
            }
            ForEach(target.risks, id: \.self) { risk in
                InlineAlert(risk.level == .high ? .danger : .warning,
                            risk.level == .high ? "AI 위험 예측 · 위험" : "AI 위험 예측 · 주의",
                            risk.message)
            }
            if target.risks.isEmpty {
                InlineAlert(.success, "사전 검증 통과", "validate · plan · 위험 설정 검사를 모두 통과했어요.")
            }
        }
    }

    // MARK: 승인 바 (아래 고정)

    private func approvalBar(_ plan: Plan) -> some View {
        let create = plan.targets.reduce(0) { $0 + $1.counts.create }
        let update = plan.targets.reduce(0) { $0 + $1.counts.update }
        let delete = plan.targets.reduce(0) { $0 + $1.counts.delete }
        let commit = deployment.map { String($0.commit.prefix(7)) }
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) { barText(plan, create, update, delete, commit); Spacer(); barButtons(plan) }
            VStack(alignment: .leading, spacing: 10) { barText(plan, create, update, delete, commit); barButtons(plan) }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface(in: .rect(cornerRadius: 16))
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    private func barText(_ plan: Plan, _ c: Int, _ u: Int, _ d: Int, _ commit: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            // 웹: "3개 환경 · 리소스 +11 ~2 −0" / "검증 통과 3/3 · 이미지 a1b2c3d"
            Text("\(plan.targets.count)개 환경 · 리소스 +\(c) ~\(u) \u{2212}\(d)").font(.subheadline.weight(.semibold).monospacedDigit())
            Text("검증 통과 \(plan.targets.count)/\(plan.targets.count)" + (commit.map { " · 이미지 \($0)" } ?? ""))
                .font(.caption).foregroundStyle(.secondary)
            if let result = store.result { Text(result).font(.caption).foregroundStyle(.orange) }
            if app.isViewer { Text("읽기 전용 계정이라 승인할 수 없어요.").font(.caption).foregroundStyle(.secondary) }
        }
    }

    private func barButtons(_ plan: Plan) -> some View {
        HStack(spacing: 8) {
            Button("거절") { Task { await store.submit(.reject, using: app) } }
                .buttonStyle(.glassCapsule(height: 44))
            Button {
                if plan.hasDelete { confirmingDelete = true } else { Task { await store.submit(.approve, using: app) } }
            } label: {
                if store.isSubmitting { ProgressView().controlSize(.small) } else { Text("승인하고 배포") }
            }
            .buttonStyle(.glassCapsule(prominent: true, height: 44))
        }
        .disabled(store.isSubmitting || app.isViewer)
    }
}
