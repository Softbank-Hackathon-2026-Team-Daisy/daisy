import Foundation

/// W-12 AI 사용량 (배포 단위, 9/30 와이어프레임 수정). 합계(A-05 plan의 `ai_usage`) · 호출 기록(`GET /projects/{id}/ai-usage?deployment_id=`)
/// · 환경별 재사용 여부로 타일과 표를 만들어요 (10/1 서버 결정).
struct AIUsageSummary: Equatable {
    struct Row: Identifiable, Equatable {
        let id: String
        let at: Date?
        let targetID: String
        /// "Terraform 생성 (deploy.yaml)", "보안 그룹 0.0.0.0/0 수정", "— 검증된 스크립트 재사용"
        let task: String
        /// "2/3" 또는 "—"
        let attempt: String
        /// 서버가 확인하지 못하면 nil → "—" (0으로 채우지 않아요)
        let tokens: Int?
        let costKrw: Int?
        let result: Result
    }

    /// LLM 호출 결과예요. 모르는 값이면 성공으로 보이지 않게 "—" Terraform 검증 통과 여부와 달라요 (10/1 서버: 화면에 "호출 성공 · 실패")
    enum Result: Equatable {
        case passed, failed, noCall, unknown
        init(_ status: AIUsage.Call.Status) {
            switch status {
            case .succeeded: self = .passed
            case .failed: self = .failed
            case .unknown: self = .unknown
            }
        }

        var text: String {
            switch self {
            case .passed: .app("호출 성공")
            case .failed: .app("호출 실패")
            case .unknown: "—"
            case .noCall: .app("AI 호출 없음")
            }
        }
    }

    let calls: Int
    let tokens: Int?
    let costKrw: Int?
    let exchangeRate: Double?
    /// 검증된 스크립트를 재사용해 AI를 안 부른 환경
    let reusedTargetIDs: [String]
    let rows: [Row]

    /// - totals: plan(A-05)의 합계. 없으면 배포에 온 합계
    /// - callLog: 호출별 기록 목록. 없으면 배포에 같이 온 `items`
    init(_ deployment: Deployment, totals: AIUsage? = nil, callLog: [AIUsage.Call]? = nil) {
        let usage = totals ?? deployment.aiUsage
        let items = callLog ?? deployment.aiUsage?.items ?? []
        let reused = (deployment.targets ?? []).filter { $0.reusedScript == true }.map(\.targetId)
        calls = usage?.calls ?? items.count
        tokens = usage?.tokens ?? items.compactMap(\.tokens).reduce(0, +)
        costKrw = usage?.costKrw
        exchangeRate = usage?.exchangeRate
        reusedTargetIDs = reused
        let callRows = items.map { call in
            Row(id: call.id, at: call.at, targetID: call.targetId,
                task: call.note ?? call.title ?? (call.step == .fix ? String.app("Terraform 수정") : String.app("Terraform 생성 (deploy.yaml)")),
                attempt: call.attempt.map { "\($0)/3" } ?? "—",
                tokens: call.tokens, costKrw: call.costKrw,
                result: Result(call.status))
        }
        // 재사용한 환경은 호출 기록이 없어서 한 줄을 따로 보여줘요 (웹 "— 검증된 스크립트 재사용")
        let reuseRows = reused.map { id in
            Row(id: "reuse-\(id)", at: deployment.createdAt, targetID: id, task: .app("— 검증된 스크립트 재사용"),
                attempt: "—", tokens: 0, costKrw: 0, result: .noCall)
        }
        rows = callRows.sorted { ($0.at ?? .distantPast) > ($1.at ?? .distantPast) } + reuseRows
    }

    /// 웹 "dep_42 · a1b2c3d · 21:10 배포" — 시각은 24시간제
    static func pickerTitle(_ deployment: Deployment, timeZone: TimeZone = .current) -> String {
        let format = Date.VerbatimFormatStyle(
            format: "\(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased)):\(minute: .twoDigits)",
            timeZone: timeZone, calendar: Calendar(identifier: .gregorian))
        let time = deployment.createdAt.map { $0.formatted(format) }
        return [deployment.version ?? deployment.id, String(deployment.commit.prefix(7)), time.map { String.app("\($0) 배포") }]
            .compactMap { $0 }.joined(separator: " · ")
    }
}

/// W-12 전체 사용량 (10/3 앱 추가): 이 프로젝트의 배포마다 plan(A-05) 합계를 더해요. 서버에 프로젝트 합계 API가 없어서 앱이 더해요.
/// 확인하지 못한 토큰 · 비용은 0으로 치지 않고 "일부"로 알려요.
struct AIUsageTotals: Equatable {
    struct Row: Identifiable, Equatable {
        let deployment: Deployment
        let calls: Int
        let tokens: Int?
        let costKrw: Int?
        let reusedTargets: Int
        var id: String { deployment.id }
    }

    let rows: [Row]
    let calls: Int
    /// 확인한 토큰만 더한 값. 하나도 없으면 nil
    let tokens: Int?
    let costKrw: Int?
    let exchangeRate: Double?
    /// 토큰이나 비용을 확인하지 못한 호출이 있어요 → 합계는 "확인한 것만"
    let isPartial: Bool
    let reusedTargets: Int
    /// AI를 한 번이라도 부른 배포 수
    let deploymentsWithCalls: Int

    /// - usages: 배포 id → plan 합계 (없으면 배포에 온 합계)
    init(_ deployments: [Deployment], usages: [String: AIUsage]) {
        rows = deployments.map { deployment in
            let usage = usages[deployment.id] ?? deployment.aiUsage
            return Row(deployment: deployment, calls: usage?.calls ?? 0, tokens: usage?.tokens, costKrw: usage?.costKrw,
                       reusedTargets: (deployment.targets ?? []).filter { $0.reusedScript == true }.count)
        }
        calls = rows.map(\.calls).reduce(0, +)
        let knownTokens = rows.compactMap(\.tokens)
        tokens = knownTokens.isEmpty ? nil : knownTokens.reduce(0, +)
        let knownCost = rows.compactMap(\.costKrw)
        costKrw = knownCost.isEmpty ? nil : knownCost.reduce(0, +)
        exchangeRate = deployments.compactMap { usages[$0.id]?.exchangeRate }.first
        isPartial = deployments.contains { deployment in
            guard let usage = usages[deployment.id] ?? deployment.aiUsage, (usage.calls ?? 0) > 0 else { return false }
            return usage.tokens == nil || usage.costKrw == nil || (usage.unknownCalls ?? 0) > 0
        }
        reusedTargets = rows.map(\.reusedTargets).reduce(0, +)
        deploymentsWithCalls = rows.filter { $0.calls > 0 }.count
    }
}
