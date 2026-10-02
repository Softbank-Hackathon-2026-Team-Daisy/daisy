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
