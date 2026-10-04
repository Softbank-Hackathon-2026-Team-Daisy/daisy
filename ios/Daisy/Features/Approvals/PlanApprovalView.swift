import SwiftUI

/// W-06 변경 사항 확인 후 승인: 환경별 요약 · 환경 탭 · plan 리소스 · 아래 고정 승인 바.
/// 규칙은 웹 `ApprovePage`와 같아요: 승인 대기 환경만 승인하고(실패한 환경은 "이번 승인에서 빠져요"),
/// 삭제가 있으면 프로젝트 이름을 입력해야 승인할 수 있어요. 거절하면 개요로 돌아가요.
///
/// 최신 상태 (10/3 검수 A1 – A4 · P4):
/// - 배포 화면 안(`onDecision` 있음): 배포 화면이 받은 배포를 계속 넘겨줘요. 승인 상태가 바뀌면 plan도 다시 받아요.
/// - 따로 연 화면(개요 · 이력 · 알림): 배포 채널(다른 배포 채널이 열려 있지 않을 때) + 3초 폴링으로 직접 받고,
///   apply가 시작되거나 배포가 끝나면 배포 화면으로 바꿔 끼워요.
struct PlanApprovalView: View {
    let deploymentID: String
    /// 배포 화면이 넘겨준 최신 배포. 바뀌면 다시 반영해요
    var deployment: Deployment?
    /// 승인하면 true, 거절하면 false. 없으면 승인은 배포 화면으로 바꿔 끼워요.
    var onDecision: ((Bool) -> Void)?
    @Environment(AppModel.self) private var app
    @Environment(Router.self) private var router
    @Environment(Workspace.self) private var workspace
    @State private var store: PlanApprovalStore
    @State private var selectedTarget: String?
    /// 따로 연 화면의 배포 채널
    @State private var channel = LiveChannel()
    /// 이 화면이 열린 탭. 요청을 기다리는 동안 탭을 옮겨도 이 탭 경로만 바꿔요 (D13)
    @State private var hostTab: AppTab?

    init(deploymentID: String, deployment: Deployment? = nil, onDecision: ((Bool) -> Void)? = nil) {
        self.deploymentID = deploymentID
        self.deployment = deployment
        self.onDecision = onDecision
        _store = State(initialValue: PlanApprovalStore(deploymentID: deploymentID, deployment: deployment))
    }

    private var isEmbedded: Bool { onDecision != nil }

    /// 배포가 승인 단계를 지났어요 (apply 시작 · 끝 · 다시 생성)
    private var movedOn: Bool {
        store.deployment.map { RunStage($0) != .approval } ?? false
    }

    var body: some View {
        content
            .transformEnvironment(\.flowRefreshIssue) { issue in
                // 배포 화면의 표시를 지우지 않게, 이 화면이 실패했을 때만 덮어써요
                if let message = store.refreshError {
                    issue = FlowRefreshIssue(message: message) { await store.load(using: app) }
                }
            }
            .onAppear { if hostTab == nil { hostTab = router.tab } }
            .task(id: isEmbedded) {
                if isEmbedded {
                    await store.load(using: app)
                    return
                }
                // 따로 연 화면: 이벤트(배포 채널 → refreshSoon)가 오면 바로, 아니면 SSE 15초 · 끊기면 3초
                await poll(on: workspace.live.changes, every: { workspace.isLive ? PollInterval.whileLive : 3 },
                           until: { movedOn }) {
                    if store.plan.value == nil { await store.load(using: app) } else { await store.refresh(using: app) }
                }
            }
            // 따로 연 화면만 배포 채널을 열어요. 이미 다른 배포 채널(밑에 깔린 배포 화면)이 열려 있으면 그쪽 신호와 폴링으로 버텨요
            .task(id: RunRefresh.wantsChannel(store.deployment?.state)) {
                guard !isEmbedded, RunRefresh.wantsChannel(store.deployment?.state), !workspace.projectChannelPaused,
                      let stream = app.eventStream else { return }
                channel.onChange = { [workspace] in workspace.refreshSoon() }
                workspace.hold(channel)
                defer { workspace.release(channel) }
                await channel.listen(stream, path: "deployments/\(deploymentID)/events")
            }
            // 배포 화면 안: 배포 화면이 새로 받은 배포를 넘겨주면 반영하고, 승인 상태가 바뀌었으면 plan도 다시 받아요 (A1)
            .onChange(of: deployment) { _, latest in
                guard let latest else { return }
                Task { await store.reloadPlanIfNeeded(after: latest, using: app) }
            }
            // 따로 연 화면: apply가 시작되거나 끝났으면 배포 화면으로 바꿔 끼워요 (A3). 배포 탭이면 루트가 이어받아요
            .onChange(of: movedOn) { _, moved in
                guard moved, !isEmbedded, store.decided == nil else { return }
                router.replaceTop(with: .run(deploymentID), in: hostTab ?? router.tab)
            }
            .onChange(of: store.decided) { _, decided in
                guard let decided else { return }
                // 사이드바 승인 대기 배지 · 개요 · 배포 목록도 바로 다시 받아요 (A6)
                workspace.refreshSoon()
                let tab = hostTab ?? router.tab
                if decided == .reject {
                    // 웹: Q1(거절하면 어디로)이 정해지기 전까지는 개요로 돌아가요
                    // 이동 기록에는 한 번만 남겨요 (경로 비우기 + 메뉴 바꾸기를 한 칸으로)
                    router.recordingOnce {
                        router.path(for: tab).wrappedValue = []
                        router.tab = .overview
                    }
                } else if let onDecision {
                    onDecision(true)
                } else {
                    router.replaceTop(with: .run(deploymentID), in: tab)
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        if store.deployment == nil, let error = store.deploymentError {
            // 배포(A-04)를 못 받았는데 "승인할 plan이 없어요"로 가리지 않아요 (A7)
            FlowPage(step: 5, title: .app("변경 사항 확인 후 승인"), description: "") {
                InlineAlert(.danger, .app("배포 정보를 불러오지 못했어요"), error)
                FlowButtons {
                    Button("다시 시도") { Task { await store.load(using: app) } }
                        .buttonStyle(.glassCapsule)
                }
            }
        } else {
            LoadStateView(state: store.plan, retry: { await store.load(using: app) }) { plan in
                let model = Model(plan: plan, deployment: store.deployment)
                switch ApprovalPhase(deployment: store.deployment, approvable: model.approvable.count,
                                     approvedWaiting: model.approvedWaiting.count) {
                case .approvable: approvalPage(model)
                case .approvedWaiting, .nothing, .movedOn: waitingPage(model)
                }
            }
        }
    }

    /// 승인할 환경이 없어요: 승인 완료 · 실행 대기, 다른 곳에서 처리됨 · plan 만료, 아직 검증 중
    private func waitingPage(_ model: Model) -> some View {
        FlowPage(step: 5, title: .app("변경 사항 확인 후 승인"), description: "") {
            if !model.approvedWaiting.isEmpty {
                // 웹 #64: 승인은 끝났고 Jenkins가 apply를 시작하기를 기다려요
                InlineAlert(.success, .app("승인 완료 · 실행 대기"), .app("승인한 plan을 적용하려고 기다리고 있어요."))
            } else if model.replaced {
                // plan.stale · 다른 곳에서 거절 · 만료: 승인 바를 띄우면 409라서 내려요
                InlineAlert(.warning, .app("plan이 만료됐거나 바뀌었어요"),
                            .app("다른 곳에서 처리했거나 plan이 다시 만들어졌어요. 새 plan이 오면 이 화면이 바로 바뀌어요."))
            } else {
                InlineAlert(.info, .app("승인을 기다리는 plan이 없어요"), .app("이미 처리됐거나 아직 검증 중이에요."))
            }
            // 배포 화면 안이든 따로 연 화면이든 상태를 계속 받아서, apply가 시작되면 저절로 "배포 중"으로 넘어가요 (10/3)
            Label("배포가 시작되면 이 화면이 자동으로 넘어가요.", systemImage: "arrow.triangle.2.circlepath")
                .font(.subheadline).foregroundStyle(.secondary)
            if !isEmbedded {
                // 따로 연 승인 화면(알림 · 이력에서)일 때만 배포 화면으로 바꿔 끼워요
                FlowButtons {
                    Button("배포 진행 보기") { router.replaceTop(with: .run(deploymentID), in: hostTab ?? router.tab) }
                        .buttonStyle(.glassCapsule)
                }
            }
        }
    }

    private func approvalPage(_ model: Model) -> some View {
        FlowPage(step: 5, title: .app("변경 사항 확인 후 승인"),
                 description: .app("환경별 plan 결과예요. 승인하면 선택한 모든 환경에 동시에 적용해요.")) {
            summary(model)
            // 고른 탭이 새 plan에 없으면 기본 탭으로 (승인 상태가 바뀌어 환경이 빠진 경우)
            let tab = selectedTarget.flatMap { model.targetIDs.contains($0) ? $0 : nil } ?? model.defaultTab
            EnvironmentTabs(selection: Binding(get: { tab }, set: { selectedTarget = $0 }), targetIDs: model.targetIDs)
            if let tab { planCard(tab, model) }
            if model.hasDelete { deleteConfirm }
            if let error = store.errorMessage { InlineAlert(.danger, .app("처리하지 못했어요"), error) }
        } bottom: {
            approvalBar(model)
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
        /// 승인이 만료 · 교체 · 거절됐어요 (plan.stale · 다른 곳에서 처리)
        let replaced: Bool

        init(plan: Plan, deployment: Deployment?) {
            self.plan = plan
            let targets = deployment?.targets ?? []
            targetIDs = targets.isEmpty ? plan.targets.map(\.targetId) : targets.map(\.targetId)
            failed = targets.filter { $0.resolvedState == .failed }
            approvedWaiting = targets.filter(\.isApprovedWaiting)
            let waiting = Set(targets.filter { $0.resolvedState == .awaitingApproval && !$0.isApprovedWaiting }.map(\.targetId))
            approvable = plan.targets.filter { targets.isEmpty || waiting.contains($0.targetId) }
            replaced = targets.contains { [.expired, .superseded, .rejected].contains($0.approvalState) }
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

    /// 삭제 확인에 입력할 이름: 이 배포의 프로젝트 이름 (웹과 같아요). 지금 고른 프로젝트가 아니라 배포의 `project_id`로 찾아요 (A4).
    /// 못 찾으면 빈 값 → 승인 버튼을 막아요
    private var confirmWord: String {
        guard let projectID = store.deployment?.projectId else { return "" }
        return workspace.projects.first { $0.id == projectID }?.name ?? ""
    }


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
            if confirmWord.isEmpty {
                // 배포의 프로젝트 이름을 아직 모르면 확인할 수 없어서 승인을 막아요 (A4)
                InlineAlert(.danger, .app("삭제되는 리소스가 있어요"), .app("이 배포의 프로젝트 이름을 불러오지 못해서 지금은 승인할 수 없어요."))
            } else {
                InlineAlert(.danger, .app("삭제되는 리소스가 있어요"), .app("확인을 위해 프로젝트 이름(\(confirmWord))을 입력해 주세요."))
                TextField(confirmWord, text: $store.confirmText)
                    .plainInput()
                    .textFieldStyle(.roundedBorder)
            }
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
