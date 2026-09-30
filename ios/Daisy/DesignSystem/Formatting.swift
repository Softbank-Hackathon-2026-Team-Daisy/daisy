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
        case .unknown: StatusBadge(text: "확인 안 됨", color: .gray)
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
        case .cancelled: StatusBadge(text: "취소", color: .gray)
        case .unknown: StatusBadge(text: "알 수 없음", color: .gray)
        }
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
        case .verifying: StatusBadge(text: "헬스체크 중", color: .blue)
        case .succeeded: StatusBadge(text: "성공", color: .green)
        case .failed: StatusBadge(text: "실패", color: .red)
        case .cancelled: StatusBadge(text: "취소", color: .gray)
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
        case .generate: "AI 생성"
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
        case .waiting, .unknown: .gray
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

    /// 웹 "환경별 진행" 한 줄과 같은 문구: "AI 생성 · validate 실행 중 · 시도 1/3".
    var progressText: String {
        if stepState == .failed && attempt >= 3 { return "\(attempt)회 실패 · 중단" }
        let origin = reusedScript == true ? "재사용 · 이미지 태그만 교체" : "AI 생성"
        let now: String = switch stepState {
        case .running: "\(step.displayName) 실행 중"
        case .done: "\(step.displayName) 통과"
        case .failed: "\(step.displayName) 실패"
        case .waiting, .unknown: "\(step.displayName) 대기 중"
        }
        return [origin, now, attemptText].joined(separator: " · ")
    }
}

extension Plan.Target.Counts {
    /// 웹과 같은 표기: "리소스 +6 ~0 −0" (빼기는 U+2212).
    var summaryText: String { "리소스 +\(create) ~\(update) \u{2212}\(delete)" }
}

extension AIUsage {
    /// 고정 환율로 환산한 추정치라 "추정"과 환율을 같이 보여줘요.
    var costText: String? {
        guard let costKrw else { return nil }
        var text = "추정 ₩\(costKrw.formatted())"
        if let exchangeRate {
            text += " (환율 \(exchangeRate.formatted(.number.precision(.fractionLength(0))))원 기준)"
        }
        return text
    }
}
