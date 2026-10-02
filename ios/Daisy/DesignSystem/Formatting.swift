import SwiftUI

extension TargetType {
    var displayName: String {
        switch self {
        case .onprem: "온프레미스"
        case .aws: "AWS"
        case .gcp: "GCP"
        case .unknown: "알 수 없는 환경"
        }
    }
}

extension Health {
    var badge: StatusBadge {
        switch self {
        case .healthy: StatusBadge(text: "정상", color: .green)
        case .unhealthy: StatusBadge(text: "이상", color: .red)
        case .unknown: StatusBadge(text: "확인 전", color: .gray)
        }
    }
}

extension DeploymentState {
    var badge: StatusBadge {
        switch self {
        // 문구는 웹 Status Badge와 같아요. 색은 앱 패턴.
        case .queued: StatusBadge(text: "대기 중", color: .gray)
        case .running: StatusBadge(text: "진행 중", color: .blue)
        case .awaitingApproval: StatusBadge(text: "승인 대기", color: .orange)
        case .succeeded: StatusBadge(text: "성공", color: .green)
        case .partiallySucceeded: StatusBadge(text: "일부 성공", color: .orange)
        case .failed: StatusBadge(text: "실패", color: .red)
        case .cancelled: StatusBadge(text: "취소됨", color: .gray)
        case .unknown: StatusBadge(text: "알 수 없음", color: .gray)
        }
    }
}

extension Deployment {
    /// 웹 `deploymentStatus`: 롤백 배포가 성공하면 "롤백됨"(보라), 나머지는 전체 상태 그대로.
    var badge: StatusBadge {
        if isRollback && state == .succeeded { return StatusBadge(text: "롤백됨", color: .purple) }
        return state.badge
    }
}

extension TargetState {
    var badge: StatusBadge {
        switch self {
        case .waiting: StatusBadge(text: "대기 중", color: .gray)
        case .generating: StatusBadge(text: "생성 중", color: .blue)
        case .validating: StatusBadge(text: "검증 중", color: .blue)
        case .awaitingApproval: StatusBadge(text: "승인 대기", color: .orange)
        case .applying: StatusBadge(text: "배포 중", color: .blue)
        case .verifying: StatusBadge(text: "확인 중", color: .blue)
        case .succeeded: StatusBadge(text: "성공", color: .green)
        case .failed: StatusBadge(text: "실패", color: .red)
        case .cancelled: StatusBadge(text: "취소됨", color: .gray)
        case .unknown: StatusBadge(text: "알 수 없음", color: .gray)
        }
    }
}

extension Deployment.Target {
    /// apply까지 갔는지. 서버가 `state`를 주면 그걸로, 아니면 단계로 판단해요.
    var reachedApply: Bool {
        switch state {
        case .applying, .verifying, .succeeded: true
        case .waiting, .generating, .validating, .awaitingApproval: false
        // 실패 · 취소 · 모름은 어느 단계에서 멈췄는지로 판단해요
        case .failed, .cancelled, .unknown, nil: [.apply, .healthCheck].contains(step)
        }
    }

    var isFailed: Bool { state == .failed || stepState == .failed }
}

extension DeploymentStep {
    var displayName: String {
        switch self {
        case .generate: "생성"
        case .validate: "validate"
        case .plan: "plan"
        case .riskCheck: "위험 설정 검사"
        case .apply: "apply"
        case .healthCheck: "헬스체크"
        case .unknown: "알 수 없는 단계"
        }
    }
}

extension StepState {
    var color: Color {
        switch self {
        case .running: .blue
        case .done: .green
        case .failed: .red
        case .waiting, .skipped, .unknown: .gray
        }
    }
}

extension PipelineStatus {
    var badge: StatusBadge {
        switch self {
        case .running: StatusBadge(text: "빌드 중", color: .blue)
        case .success: StatusBadge(text: "성공", color: .green)
        case .failed: StatusBadge(text: "실패", color: .red)
        case .unknown: StatusBadge(text: "알 수 없음", color: .gray)
        }
    }
}

extension RiskLevel {
    var color: Color {
        switch self {
        case .high: .red
        case .medium: .orange
        case .low: .yellow
        case .unknown: .gray
        }
    }
}

extension Deployment.Target {
    /// 최초 생성을 포함한 총 시도 횟수. 재시도 횟수가 아니에요.
    var attemptText: String { "시도 \(attempt)/3" }

    /// 환경별 상태. 서버가 `state`를 안 주면 단계 · 단계 상태로 추정해요.
    var resolvedState: TargetState {
        if let state, state != .unknown { return state }
        if stepState == .failed { return .failed }
        switch step {
        case .generate: return stepState == .waiting ? .waiting : .generating
        case .riskCheck where stepState == .done: return .awaitingApproval
        case .apply: return stepState == .done ? .verifying : .applying
        case .healthCheck: return stepState == .done ? .succeeded : .verifying
        default: return .validating
        }
    }

    /// W-05 · W-05b 환경별 한 줄과 배지 (웹 `flow.ts` generateRow와 같은 규칙):
    /// "AI 생성 · validate 실행 중 · 시도 1/3", "재사용 · 이미지 태그만 교체 · 시도 1/3 통과", "3회 실패 · 중단"
    var generateRow: (note: String, badge: StatusBadge) {
        let how = reusedScript == true ? "재사용 · 이미지 태그만 교체" : "AI 생성"
        switch resolvedState {
        case .failed:
            return ("\(attempt)회 실패 · 중단", StatusBadge(text: "실패", color: .red))
        case .awaitingApproval, .applying, .verifying, .succeeded:
            return ("\(how) · \(attemptText) 통과", StatusBadge(text: "검증 통과", color: .green))
        case .waiting:
            return ("대기 중", TargetState.waiting.badge)
        case .generating:
            return ("\(how) · \(attemptText)", TargetState.generating.badge)
        case .cancelled:
            return ("취소됨", TargetState.cancelled.badge)
        case .validating, .unknown:
            if errorSummary != nil {
                return ("\(how) · 위험 설정 발견 → AI 수정 중 · \(attemptText)", StatusBadge(text: "검증 중", color: .blue))
            }
            return ("\(how) · \(step.displayName) 실행 중 · \(attemptText)", StatusBadge(text: "검증 중", color: .blue))
        }
    }

    /// W-05 검증 단계. 서버가 `steps`를 주면 그대로, 없으면 웹처럼 4단계로 추정해요.
    var generateSteps: [StepItem] {
        if let steps, !steps.isEmpty { return steps }
        let order: [DeploymentStep] = [.generate, .validate, .plan, .riskCheck]
        let state = resolvedState
        let done = [.awaitingApproval, .applying, .verifying, .succeeded].contains(state)
        let current = order.firstIndex(of: step) ?? -1
        return order.enumerated().map { index, step in
            let label = switch step {
            case .generate: reusedScript == true ? "스크립트 재사용" : "Terraform 생성 (AI)"
            case .riskCheck: "위험 설정 검사"
            default: "terraform \(step.displayName)"
            }
            let itemState: StepState = done || index < current ? .done
                : index == current ? (state == .failed ? .failed : state == .waiting ? .waiting : .running)
                : .waiting
            return StepItem(name: label, state: itemState, durationMs: nil, startedAt: nil)
        }
    }

    /// W-07 apply 단계. 서버가 `steps`를 주면 그대로, 없으면 웹처럼 "이미지 pull · terraform apply · state 저장 · 헬스체크".
    var applySteps: [StepItem] {
        if let steps, !steps.isEmpty { return steps }
        let state = resolvedState
        let current = switch state {
        case .verifying: 3
        case .applying: 1
        case .succeeded: 4
        case .failed: step == .healthCheck ? 3 : 1
        default: 0
        }
        return ["이미지 pull", "terraform apply", "state 저장", "헬스체크"].enumerated().map { index, label in
            let itemState: StepState = index < current ? .done
                : index == current ? (state == .failed ? .failed : state == .succeeded ? .done : .running)
                : .waiting
            return StepItem(name: label, state: itemState, durationMs: nil, startedAt: nil)
        }
    }
}

extension Plan.Target.Counts {
    /// 웹과 같은 표기: "리소스 +6 ~0 −0" (빼기는 U+2212).
    var summaryText: String { "리소스 +\(create) ~\(update) \u{2212}\(delete)" }
}

extension AIUsage {
    /// 고정 환율로 환산한 추정치라 "추정"과 환율을 같이 보여줘요. 웹 승인 바: "₩206 (추정, 환율 1,380원)"
    var costText: String? {
        guard let costKrw else { return nil }
        let rate = exchangeRate.map { ", 환율 \(Int($0).formatted())원" } ?? ""
        return "₩\(costKrw.formatted()) (추정\(rate))"
    }
}

// MARK: - 시간 표기 (웹 `utils/format.ts`와 같아요)

enum TimeText {
    private static func verbatim(_ format: Date.FormatString, _ timeZone: TimeZone) -> Date.VerbatimFormatStyle {
        Date.VerbatimFormatStyle(format: format, timeZone: timeZone, calendar: Calendar(identifier: .gregorian))
    }

    /// 웹 clockTime: 24시간제 "21:10"
    static func clock(_ date: Date, timeZone: TimeZone = .current) -> String {
        date.formatted(verbatim("\(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased)):\(minute: .twoDigits)", timeZone))
    }

    /// 로그 한 줄: 24시간제 "21:10:05"
    static func clockSeconds(_ date: Date, timeZone: TimeZone = .current) -> String {
        date.formatted(verbatim("\(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased)):\(minute: .twoDigits):\(second: .twoDigits)", timeZone))
    }

    /// 웹 "M/D HH:mm" (W-11 만든 시각)
    static func dayClock(_ date: Date, timeZone: TimeZone = .current) -> String {
        date.formatted(verbatim("\(month: .defaultDigits)/\(day: .defaultDigits) \(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased)):\(minute: .twoDigits)", timeZone))
    }

    /// 웹 relativeTime: 방금 · n분 전 · n시간 전(오늘) · 어제 · M/D
    static func relative(_ date: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        let minutes = Int(max(0, now.timeIntervalSince(date)) / 60)
        if minutes < 1 { return "방금" }
        if minutes < 60 { return "\(minutes)분 전" }
        if calendar.isDate(date, inSameDayAs: now) { return "\(minutes / 60)시간 전" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) { return "어제" }
        let parts = calendar.dateComponents([.month, .day], from: date)
        return "\(parts.month ?? 0)/\(parts.day ?? 0)"
    }
}
