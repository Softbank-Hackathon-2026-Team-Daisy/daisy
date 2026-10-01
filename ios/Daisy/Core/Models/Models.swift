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
    /// WR-09: 떠 있는 이미지의 digest. 동일성 검증("3/3 일치")의 근거예요 (9/30 서버 수락).
    let imageDigest: String?

    var id: String { targetId }
}

// MARK: - 배포 (A-03, A-04)

/// 배포 전체 상태 (9/30 서버 확정). 우선순위: 승인 대기 > 진행 중 > 전부 성공 · 섞임 · 전부 실패 > 취소.
/// 롤백은 상태가 아니라 별도 배포(`kind: "rollback"`)예요.
enum DeploymentState: String, ServerEnum {
    case queued, running
    case awaitingApproval = "awaiting_approval"
    case succeeded
    case partiallySucceeded = "partially_succeeded"
    case failed, cancelled
    case unknown
    static let unknownCase = DeploymentState.unknown

    var isFinished: Bool { [.succeeded, .partiallySucceeded, .failed, .cancelled].contains(self) }
}

/// 환경별 상태 (9/30 서버 확정).
enum TargetState: String, ServerEnum {
    case waiting, generating, validating
    case awaitingApproval = "awaiting_approval"
    case applying, verifying, succeeded, failed, cancelled
    case unknown
    static let unknownCase = TargetState.unknown
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
        /// 환경별 상태. 서버가 아직 안 보내면 nil이고 그때는 step · step_state로 판단해요.
        let state: TargetState?
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
        /// W-08 동일성 검증: 이 환경에 올라간 이미지 digest (웹 A-04 `image_digest`)
        let imageDigest: String?

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
    /// 롤백도 배포 한 건이에요: `kind: "rollback"`, `rolled_back_from` (WR-14)
    let kind: String?
    let rolledBackFrom: String?
    /// W-12: 이 배포의 AI 사용량 (9/30 서버: GET /deployments/{id}의 ai_usage)
    let aiUsage: AIUsage?

    /// 롤백도 배포 한 건이에요. 목록 · 알림에서는 일반 배포처럼 보여줘요 (9/30 도영 님).
    var isRollback: Bool { kind == "rollback" }
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
        /// W-06 환경별 요약 끝말 (웹 `summary`): "이미지 태그만 교체". 없으면 "위험 설정 n건"
        let summary: String?
        /// W-06 plan 원문 (웹 `plan_text`). 없으면 리소스 목록만 보여줘요
        let planText: String?

        var id: String { targetId }
    }

    let deploymentId: String
    let targets: [Target]
    let aiUsage: AIUsage?

    var hasDelete: Bool { targets.contains { $0.hasDelete } }
}

/// AI 사용량 합계. 원화는 고정 환율로 환산한 추정치예요.
/// 합계는 plan(A-05)에 와요 (10/1 서버). 호출별 기록은 `GET /projects/{id}/ai-usage?deployment_id=`의 `Call` 목록이에요.
/// `items`는 서버가 배포(A-04)에 같이 줄 때만 쓰는 예비 칸이에요.
struct AIUsage: Decodable, Hashable, Sendable {
    /// 실제 LLM 호출 한 번. 재사용으로 AI를 안 부른 환경은 기록이 없어요.
    struct Call: Decodable, Identifiable, Hashable, Sendable {
        enum Step: String, ServerEnum {
            case generate, fix, unknown
            static let unknownCase = Step.unknown
        }

        enum Status: String, ServerEnum {
            case succeeded, failed, unknown
            static let unknownCase = Status.unknown
        }

        let at: Date?
        let deploymentId: String?
        let targetId: String
        let step: Step
        let attempt: Int?
        /// 확인하지 못한 토큰 · 비용은 서버가 0으로 채우지 않고 비워 둬요 → 화면에 "—"
        let tokens: Int?
        let costKrw: Int?
        /// LLM 호출 성공 · 실패 (Terraform 검증 결과와 별개, 10/1 서버)
        let status: Status
        /// "보안 그룹 0.0.0.0/0 수정" 같은 한 줄 (가칭). 서버가 필수로 약속하지 않았어요 (10/1)
        let note: String?
        /// 웹 목업 이름 (`title`). `note`가 없을 때 대신 써요
        let title: String?

        var id: String { "\(at?.timeIntervalSince1970 ?? 0)-\(targetId)-\(step.rawValue)-\(attempt ?? 0)" }
    }

    let tokens: Int?
    let costKrw: Int?
    let exchangeRate: Double?
    let estimated: Bool?
    let calls: Int?
    let items: [Call]?
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
