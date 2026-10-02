import SwiftUI

/// W-06 변경 사항 확인 후 승인: 환경별 요약 · 환경 탭 · plan 리소스 · 아래 고정 승인 바.
/// 규칙은 웹 `ApprovePage`와 같아요: 승인 대기 환경만 승인하고(실패한 환경은 "이번 승인에서 빠져요"),
/// 삭제가 있으면 프로젝트 이름을 입력해야 승인할 수 있어요. 거절하면 개요로 돌아가요.
struct PlanApprovalView: View {
    let deploymentID: String
    /// 승인하면 true, 거절하면 false. 없으면 승인은 배포 화면으로 바꿔 끼워요.
    var onDecision: ((Bool) -> Void)?
    @Environment(AppModel.self) private var app
    @Environment(Router.self) private var router
    @Environment(Workspace.self) private var workspace
    @State private var store: PlanApprovalStore
    @State private var selectedTarget: String?

    init(deploymentID: String, deployment: Deployment? = nil, onDecision: ((Bool) -> Void)? = nil) {
        self.deploymentID = deploymentID
        self.onDecision = onDecision
        _store = State(initialValue: PlanApprovalStore(deploymentID: deploymentID, deployment: deployment))
    }

    var body: some View {
        LoadStateView(state: store.plan, retry: { await store.load(using: app) }) { plan in
            let model = Model(plan: plan, deployment: store.deployment)
            if model.approvable.isEmpty {
                FlowPage(step: 5, title: .app("변경 사항 확인 후 승인"), description: "") {
                    if model.approvedWaiting.isEmpty {
                        InlineAlert(.info, .app("승인을 기다리는 plan이 없어요"), .app("이미 처리됐거나 아직 검증 중이에요."))
                    } else {
                        // 웹 #64: 승인은 끝났고 Jenkins가 apply를 시작하기를 기다려요
                        InlineAlert(.success, .app("승인 완료 · 실행 대기"), .app("승인한 plan을 적용하려고 기다리고 있어요."))
                    }
                    FlowButtons {
                        Button("배포 진행 보기") { router.replaceTop(with: .run(deploymentID)) }
                            .buttonStyle(.glassCapsule)
                    }
                }
            } else {
                FlowPage(step: 5, title: .app("변경 사항 확인 후 승인"),
                         description: .app("환경별 plan 결과예요. 승인하면 선택한 모든 환경에 동시에 적용해요.")) {
                    summary(model)
                    let tab = selectedTarget ?? model.defaultTab
                    EnvironmentTabs(selection: Binding(get: { tab }, set: { selectedTarget = $0 }), targetIDs: model.targetIDs)
                    if let tab { planCard(tab, model) }
                    if model.hasDelete { deleteConfirm }
                    if let error = store.errorMessage { InlineAlert(.danger, .app("처리하지 못했어요"), error) }
                } bottom: {
                    approvalBar(model)
                }
            }
        }
        .task { await store.load(using: app) }
        .onChange(of: store.decided) { _, decided in
            guard let decided else { return }
            if decided == .reject {
                // 웹: Q1(거절하면 어디로)이 정해지기 전까지는 개요로 돌아가요
                router.popToRoot()
                router.tab = .overview
            } else if let onDecision {
                onDecision(true)
            } else {
                router.replaceTop(with: .run(deploymentID))
            }
        }
    }

    /// 승인 대기 환경 · 합계 · 위험 설정. 배포(A-04)가 아직 없으면 plan의 모든 환경을 승인 대기로 봐요.
    private struct Model {
        let plan: Plan
        let targetIDs: [String]
        let failed: [Deployment.Target]
        let approvable: [Plan.Target]
        /// 이미 승인하고 apply를 기다리는 환경 (웹 #64): 다시 승인하지 않아요
        let approvedWaiting: [Deployment.Target]

        init(plan: Plan, deployment: Deployment?) {
            self.plan = plan
            let targets = deployment?.targets ?? []
            targetIDs = targets.isEmpty ? plan.targets.map(\.targetId) : targets.map(\.targetId)
            failed = targets.filter { $0.resolvedState == .failed }
            approvedWaiting = targets.filter(\.isApprovedWaiting)
            let waiting = Set(targets.filter { $0.resolvedState == .awaitingApproval && !$0.isApprovedWaiting }.map(\.targetId))
            approvable = plan.targets.filter { targets.isEmpty || waiting.contains($0.targetId) }
        }

        /// 웹과 같아요: 두 번째 승인 대기 환경(없으면 첫 번째)부터 보여줘요
        var defaultTab: String? {
            (approvable.count > 1 ? approvable[1] : approvable.first)?.targetId ?? targetIDs.first
        }
        var hasDelete: Bool { approvable.contains { $0.hasDelete } }
        var risks: [Plan.Target.Risk] { approvable.flatMap(\.risks) }
        func sum(_ key: KeyPath<Plan.Target.Counts, Int>) -> Int { approvable.reduce(0) { $0 + $1.counts[keyPath: key] } }
        func plan(of targetID: String) -> Plan.Target? { plan.targets.first { $0.targetId == targetID } }
    }

    /// 삭제 확인에 입력할 이름: 프로젝트 이름 (웹과 같아요)
    private var confirmWord: String { workspace.project?.name ?? "" }

    // MARK: 환경별 요약

    private func summary(_ model: Model) -> some View {
        SectionCard(.app("환경별 요약")) {
            VStack(spacing: 10) {
                ForEach(model.targetIDs, id: \.self) { id in
                    let type = workspace.type(of: id)
                    if let failed = model.failed.first(where: { $0.targetId == id }) {
                        ProgressLine(name: type, text: .app("\(failed.attempt)회 실패 · 이번 승인에서 빠져요")) {
                            StatusBadge(text: .app("실패"), color: .red)
                        }
                    } else {
                        // 웹: "리소스 +6 ~0 −0 · 위험 설정 0건" (앱은 "리소스 생성 6 · 변경 0 · 삭제 0 · 위험 설정 0건")
                        let target = model.plan(of: id)
                        let text = target.map { "\($0.counts.summaryText) · \($0.summary ?? String.app("위험 설정 \($0.risks.count)건"))" } ?? "—"
                        ProgressLine(name: type, text: text) { StatusBadge(text: .app("검증 통과"), color: .green) }
                    }
                }
            }
        }
    }

    // MARK: 환경 plan

    private func planCard(_ targetID: String, _ model: Model) -> some View {
        SectionCard("\(workspace.name(of: targetID)) plan") {
            if let target = model.plan(of: targetID) {
                VStack(spacing: 4) {
                    ForEach(target.resources ?? [], id: \.self) { ResourceDiffRow(resource: $0) }
                }
                if (target.resources ?? []).isEmpty {
                    Text(target.counts.summaryText).font(.subheadline.monospacedDigit())
                }
                if target.risks.isEmpty {
                    InlineAlert(.success, .app("사전 검증 통과"), .app("validate · plan · 위험 설정 검사를 모두 통과했어요."))
                } else {
                    ForEach(target.risks, id: \.self) { risk in
                        InlineAlert(.warning, .app("위험 설정 · \(risk.level.rawValue)"),
                                    risk.message + (risk.resource.map { " (\($0))" } ?? ""))
                    }
                }
                if let planText = target.planText {
                    CodeBlock(header: "\(workspace.type(of: targetID).rawValue) · terraform plan", aiGenerated: false, code: planText)
                }
            } else {
                Text("이 환경은 plan이 없어요.").foregroundStyle(.secondary)
            }
        }
    }

    /// 삭제가 있으면 프로젝트 이름을 입력해야 승인 버튼이 열려요 (서버도 confirm_text를 검증해요)
    private var deleteConfirm: some View {
        @Bindable var store = store
        return VStack(alignment: .leading, spacing: 8) {
            InlineAlert(.danger, .app("삭제되는 리소스가 있어요"), .app("확인을 위해 프로젝트 이름(\(confirmWord))을 입력해 주세요."))
            TextField(confirmWord, text: $store.confirmText)
                .plainInput()
                .textFieldStyle(.roundedBorder)
        }
    }

    // MARK: 승인 바 (아래 고정)

    private func approvalBar(_ model: Model) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) { barText(model); Spacer(); barButtons(model) }
            VStack(alignment: .leading, spacing: 10) { barText(model); barButtons(model) }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface(in: .rect(cornerRadius: 16))
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    private func barText(_ model: Model) -> some View {
        // 웹: "2개 환경 · 리소스 +3 ~1 −1" (앱은 "2개 환경 · 생성 3 · 변경 1 · 삭제 1") / "검증 통과 2/3 · 이미지 a1b2c3d · 위험 설정 1건 · AI 비용 ₩206 (추정, 환율 1,380원)"
        let meta: String = ([
            .app("검증 통과 \(model.approvable.count)/\(model.targetIDs.count)"),
            store.deployment.map { String.app("이미지 \(String($0.commit.prefix(7)))") },
            .app("위험 설정 \(model.risks.count)건"),
            model.plan.aiUsage?.costText.map { String.app("AI 비용 \($0)") },
        ] as [String?]).compactMap { $0 }.joined(separator: " · ")
        return VStack(alignment: .leading, spacing: 2) {
            Text("\(model.approvable.count)개 환경 · 생성 \(model.sum(\.create)) · 변경 \(model.sum(\.update)) · 삭제 \(model.sum(\.delete))")
                .font(.subheadline.weight(.semibold).monospacedDigit())
            Text(meta).font(.caption).foregroundStyle(.secondary)
            if app.isViewer { Text("읽기 전용 계정이라 승인할 수 없어요.").font(.caption).foregroundStyle(.orange) }
        }
    }

    private func barButtons(_ model: Model) -> some View {
        // 프로젝트 이름을 못 불러왔으면 확인할 수 없으니 막아요
        let needsConfirm = model.hasDelete && (confirmWord.isEmpty || store.confirmText != confirmWord)
        return HStack(spacing: 8) {
            Button("거절") { Task { await store.submit(.reject, needsConfirm: false, targetIDs: model.approvable.map(\.targetId), using: app) } }
                .buttonStyle(.glassCapsule(height: 44))
            Button(store.isSubmitting ? "승인하는 중…" : "승인하고 배포") {
                Task { await store.submit(.approve, needsConfirm: model.hasDelete, targetIDs: model.approvable.map(\.targetId), using: app) }
            }
            .buttonStyle(.glassCapsule(prominent: true, height: 44))
            .disabled(needsConfirm)
        }
        .disabled(store.isSubmitting || app.isViewer)
    }
}
