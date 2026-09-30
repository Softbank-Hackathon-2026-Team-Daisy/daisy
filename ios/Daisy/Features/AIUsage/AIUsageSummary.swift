import Foundation

/// W-12 AI 사용량 (배포 단위, 9/30 와이어프레임 수정). 배포 한 건의 `ai_usage`와 환경별 재사용 여부로 타일과 표를 만들어요.
struct AIUsageSummary: Equatable {
    struct Row: Identifiable, Equatable {
        let id: String
        let at: Date?
        let targetID: String
        /// "Terraform 생성 (deploy.yaml)", "보안 그룹 0.0.0.0/0 수정", "— 검증된 스크립트 재사용"
        let task: String
        /// "2/3" 또는 "—"
        let attempt: String
        let tokens: Int
        let costKrw: Int?
        let result: Result
    }

    enum Result: Equatable {
        case passed, failed, noCall
        var text: String {
            switch self {
            case .passed: "통과"
            case .failed: "실패"
            case .noCall: "AI 호출 없음"
            }
        }
    }

    let calls: Int
    let tokens: Int
    let costKrw: Int?
    let exchangeRate: Double?
    /// 검증된 스크립트를 재사용해 AI를 안 부른 환경
    let reusedTargetIDs: [String]
    let rows: [Row]

    init(_ deployment: Deployment) {
        let usage = deployment.aiUsage
        let items = usage?.items ?? []
        let reused = (deployment.targets ?? []).filter { $0.reusedScript == true }.map(\.targetId)
        calls = usage?.calls ?? items.count
        tokens = usage?.tokens ?? items.compactMap(\.tokens).reduce(0, +)
        costKrw = usage?.costKrw
        exchangeRate = usage?.exchangeRate
        reusedTargetIDs = reused
        let callRows = items.map { call in
            Row(id: call.id, at: call.at, targetID: call.targetId,
                task: call.note ?? (call.step == .fix ? "Terraform 수정" : "Terraform 생성 (deploy.yaml)"),
                attempt: call.attempt.map { "\($0)/3" } ?? "—",
                tokens: call.tokens ?? 0, costKrw: call.costKrw,
                result: call.status == .failed ? .failed : .passed)
        }
        // 재사용한 환경은 호출 기록이 없어서 한 줄을 따로 보여줘요 (웹 "— 검증된 스크립트 재사용")
        let reuseRows = reused.map { id in
            Row(id: "reuse-\(id)", at: nil, targetID: id, task: "— 검증된 스크립트 재사용",
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
        return [deployment.version ?? deployment.id, String(deployment.commit.prefix(7)), time.map { "\($0) 배포" }]
            .compactMap { $0 }.joined(separator: " · ")
    }
}
