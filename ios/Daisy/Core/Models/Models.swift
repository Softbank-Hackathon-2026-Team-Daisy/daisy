import Foundation

// SPEC §6-7과 1:1. `Plan`은 서버 PlanSummary 기준으로 확정, 나머지 필드는 서버 OpenAPI가 나오면 맞춰요 (가칭).

/// 목록 응답 공통 봉투 `{ items, next_cursor }` (v0.1 공통 규칙).
struct Page<Item: Decodable & Sendable>: Decodable, Sendable {
    let items: [Item]
    let nextCursor: String?
}

struct Project: Decodable, Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let repository: String?
    /// 배포 기준 브랜치 (가칭)
    let branch: String?
}

// MARK: - 현황 (A-02)

enum TargetType: String, ServerEnum {
    case onprem, aws, gcp, unknown
    static let unknownCase = TargetType.unknown
}

enum Health: String, ServerEnum {
    case healthy, unhealthy, unknown
    static let unknownCase = Health.unknown
}

struct TargetStatus: Decodable, Identifiable, Hashable, Sendable {
    struct Release: Decodable, Hashable, Sendable {
        let commit: String
        let image: String?
        let deploymentId: String?
        let deployedAt: Date?
    }

    let targetId: String
    let type: TargetType
    let name: String
    let current: Release?
    let url: URL?
    let health: Health
    let checkedAt: Date?

    var id: String { targetId }
}

// MARK: - 배포 (A-03, A-04)

enum DeploymentState: String, ServerEnum {
    case queued
    /// 웹 흐름 W-03 · W-04 · W-05b 단계 (가칭)
    case building
    case selectingTargets = "selecting_targets"
    case generating, validating
    case awaitingApproval = "awaiting_approval"
    case applying, succeeded, failed, cancelled
    case stopped
    /// 웹 Status Badge에 있는 상태. 서버 상태 이름이 확정되면 맞춰요 (가칭).
    case warning
    case rolledBack = "rolled_back"
    case unknown
    static let unknownCase = DeploymentState.unknown

    var isFinished: Bool { [.succeeded, .failed, .cancelled, .stopped, .rolledBack].contains(self) }
}

enum DeploymentStep: String, ServerEnum {
    case generate, validate, plan
    case riskCheck = "risk_check"
    case apply
    case healthCheck = "health_check"
    case unknown
    static let unknownCase = DeploymentStep.unknown
}

enum StepState: String, ServerEnum {
    case running, done, failed, waiting, unknown
    static let unknownCase = StepState.unknown
}

struct Deployment: Decodable, Identifiable, Hashable, Sendable {
    struct Target: Decodable, Identifiable, Hashable, Sendable {
        let targetId: String
        let step: DeploymentStep
        let stepState: StepState
        /// 최초 생성을 포함한 총 시도 횟수 (1~3). 화면에는 "시도 n/3".
        let attempt: Int
        let reusedScript: Bool?
        let url: URL?
        let errorSummary: String?
        /// 레인 부제 (가칭): "home-lab · Docker", "ap-northeast-2 · ECS Fargate"
        let title: String?
        /// 단계 줄 (가칭): W-05 검증 단계, W-07 배포 단계
        let steps: [StepItem]?
        /// W-08 헬스 요약 (가칭): "200 OK · p95 120ms"
        let healthSummary: String?

        var id: String { targetId }
    }

    struct PendingApproval: Decodable, Hashable, Sendable {
        let approvalId: String
        let kind: String
    }

    let id: String
    let projectId: String
    let commit: String
    let image: String?
    /// 웹 W-09 "버전" 열 (가칭): "v7"
    let version: String?
    /// 웹 실행 목록의 커밋 메시지 (가칭)
    let commitMessage: String?
    let state: DeploymentState
    let targets: [Target]?
    let pendingApproval: PendingApproval?
    let createdBy: String?
    let createdAt: Date?
    let finishedAt: Date?
}

// MARK: - 승인 (A-05, W-01)

enum RiskLevel: String, ServerEnum {
    case high, medium, low, unknown
    static let unknownCase = RiskLevel.unknown
}

struct Plan: Decodable, Sendable {
    struct Target: Decodable, Identifiable, Sendable {
        struct Counts: Decodable, Sendable {
            let create: Int
            let update: Int
            let delete: Int
        }

        struct Risk: Decodable, Hashable, Sendable {
            let level: RiskLevel
            let rule: String
            let resource: String?
            let message: String
        }

        let targetId: String
        let counts: Counts
        /// 리소스 교체(replace)로 삭제가 생겨도 true.
        let hasDelete: Bool
        let risks: [Risk]
        /// 검증된 스크립트 재사용이면 true → "이미지 태그만 교체" (가칭)
        let reusedScript: Bool?
        /// W-06 리소스 변경 행 (가칭)
        let resources: [PlanResource]?

        var id: String { targetId }
    }

    let deploymentId: String
    let targets: [Target]
    let aiUsage: AIUsage?

    var hasDelete: Bool { targets.contains { $0.hasDelete } }
}

/// AI 비용 누적 합계. 원화는 고정 환율로 환산한 추정치예요 (가칭).
struct AIUsage: Decodable, Sendable {
    let tokens: Int?
    let costKrw: Int?
    let exchangeRate: Double?
    let estimated: Bool?
}

enum ApprovalDecision: String, Encodable, Sendable {
    case approve, reject
}

// MARK: - 커밋 · 파이프라인 (A-06)

enum PipelineStatus: String, ServerEnum {
    case running, success, failed, unknown
    static let unknownCase = PipelineStatus.unknown
}

struct Build: Decodable, Identifiable, Hashable, Sendable {
    struct Pipeline: Decodable, Hashable, Sendable {
        let status: PipelineStatus
        let runUrl: URL?
    }

    struct DeployedTarget: Decodable, Hashable, Sendable {
        let targetId: String
        let deploymentId: String
        let deployedAt: Date?
    }

    let commit: String
    let message: String
    let author: String
    let committedAt: Date?
    let pipeline: Pipeline
    let image: String?
    let deployedTo: [DeployedTarget]
    /// W-03 이미지 카드 · 단계 (가칭)
    let branch: String?
    let digest: String?
    let steps: [StepItem]?

    var id: String { commit }
}

// MARK: - 인증 (R-02)

struct AuthToken: Decodable, Sendable {
    let accessToken: String
    let expiresAt: Date?
    let role: String

    /// 데모 읽기 전용 계정 (R-03). 승인하면 403이 와요.
    var isViewer: Bool { role == "viewer" }
}
