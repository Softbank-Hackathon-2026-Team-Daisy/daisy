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
        case .queued: StatusBadge(text: "대기", color: .gray)
        case .generating: StatusBadge(text: "생성 중", color: .blue)
        case .validating: StatusBadge(text: "검증 중", color: .blue)
        case .awaitingApproval: StatusBadge(text: "승인 대기", color: .orange)
        case .applying: StatusBadge(text: "배포 중", color: .blue)
        case .succeeded: StatusBadge(text: "완료", color: .green)
        case .failed: StatusBadge(text: "실패", color: .red)
        case .cancelled: StatusBadge(text: "취소", color: .gray)
        case .unknown: StatusBadge(text: "알 수 없음", color: .gray)
        }
    }
}

extension DeploymentStep {
    var displayName: String {
        switch self {
        case .generate: "생성"
        case .validate: "validate"
        case .plan: "plan"
        case .riskCheck: "위험 검사"
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
