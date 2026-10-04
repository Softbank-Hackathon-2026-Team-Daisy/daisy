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
    /// 배포 기준 브랜치. 서버(#38)는 `default_branch`로 줘요. 예전 이름 `branch`도 받아요
    let branch: String?

    private enum CodingKeys: String, CodingKey { case id, name, repository, branch, defaultBranch }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        repository = try c.decodeIfPresent(String.self, forKey: .repository)
        branch = try c.decodeIfPresent(String.self, forKey: .defaultBranch) ?? c.decodeIfPresent(String.self, forKey: .branch)
    }
}

// MARK: - 현황 (A-02)

enum TargetType: String, ServerEnum {
    case onprem, aws, gcp, azure, unknown  // azure: 10/2 회의로 포함 (웹 #87)
    static let unknownCase = TargetType.unknown
}

enum Health: String, ServerEnum {
    case healthy, unhealthy, unknown
    static let unknownCase = Health.unknown
}

/// A-02 현재 배포 확인 결과. `none` = 확인된 참조 없음(배포가 없다는 뜻은 아니에요), `unverified` = 참조는 있지만 확인 실패
enum CurrentStatus: String, ServerEnum {
    case none, confirmed, unverified, unknown
    static let unknownCase = CurrentStatus.unknown
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
    /// `current`를 확인했는지 (10/2 01:10 서버 #42): `confirmed`일 때만 `current`가 와요
    let currentStatus: CurrentStatus?
    let current: Release?
    let url: URL?
    let health: Health
    let checkedAt: Date?
    /// WR-09: 떠 있는 이미지의 digest. 동일성 검증("3/3 일치")의 근거예요 (9/30 서버 수락).
    let imageDigest: String?
    /// 헬스 한 줄 "200 OK · 120ms" (헬스체크 1회 측정, 10/1 임채준 답). 없으면 "정상" · "실패"
    let healthSummary: String?

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
    /// `skipped`: Jenkins가 실행하지 않은 단계(NOT_EXECUTED, 예: daisy-ci의 Trigger CD) → "건너뜀". 값 이름은 서버와 확인 중 (가칭, 웹 #25와 같아요)
    case running, done, failed, waiting, skipped, unknown
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
        /// W-08 헬스 요약 (가칭): "200 OK · 120ms" (헬스체크 1회 측정)
        let healthSummary: String?
        /// W-08 동일성 검증: 이 환경에 올라간 이미지 digest (웹 A-04 `image_digest`)
        let imageDigest: String?
        /// 이 환경 plan의 승인 상태 (서버 #56). `awaiting_approval`인데 `approved`면 "승인 완료 · 실행 대기"예요
        let approvalState: ApprovalState?
        /// apply 명령을 Jenkins에 넘긴 상태 (서버 #56): `queued` · `unknown` · `rejected`
        let applyDispatch: String?

        enum ApprovalState: String, ServerEnum {
            case pending, approved, rejected, superseded, expired, unknown
            static let unknownCase = ApprovalState.unknown
        }

        var id: String { targetId }

        /// 이미 승인했고 apply가 아직 시작 전이에요. 다시 승인하지 않아요 (웹 #64와 같아요)
        var isApprovedWaiting: Bool { resolvedState == .awaitingApproval && approvalState == .approved }

        private enum CodingKeys: String, CodingKey {
            case targetId, state, step, stepState, attempt, reusedScript, url, errorSummary, title, steps, healthSummary, imageDigest
            case approvalState, applyDispatch
        }

        /// A-04 모양은 서버가 아직 확정 전이라 단계 · 시도는 없을 수 있어요 (서버 안: 확인 전이면 null · 생략).
        /// 하나가 없다고 배포 화면 전체가 안 뜨지 않게, 없으면 모름(`unknown`) · 시도 0(생성 전)으로 읽어요
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            targetId = try c.decode(String.self, forKey: .targetId)
            state = try c.decodeIfPresent(TargetState.self, forKey: .state)
            step = try c.decodeIfPresent(DeploymentStep.self, forKey: .step) ?? .unknown
            stepState = try c.decodeIfPresent(StepState.self, forKey: .stepState) ?? .unknown
            attempt = try c.decodeIfPresent(Int.self, forKey: .attempt) ?? 0
            reusedScript = try c.decodeIfPresent(Bool.self, forKey: .reusedScript)
            url = try c.decodeIfPresent(URL.self, forKey: .url)
            errorSummary = try c.decodeIfPresent(String.self, forKey: .errorSummary)
            title = try c.decodeIfPresent(String.self, forKey: .title)
            steps = try c.decodeIfPresent([StepItem].self, forKey: .steps)
            healthSummary = try c.decodeIfPresent(String.self, forKey: .healthSummary)
            imageDigest = try c.decodeIfPresent(String.self, forKey: .imageDigest)
            approvalState = try c.decodeIfPresent(ApprovalState.self, forKey: .approvalState)
            applyDispatch = try c.decodeIfPresent(String.self, forKey: .applyDispatch)
        }
    }

    /// 승인 요청 한 항목: 사용자가 화면에서 본 승인 대기 환경 (10/1 22:39 서버 확정, #36 · #40)
    struct ApprovalItem: Codable, Hashable, Sendable {
        let targetId: String
        let approvalId: String
    }

    struct PendingApproval: Decodable, Hashable, Sendable {
        let approvalId: String
        let kind: String
    }

    let id: String
    let projectId: String
    let commit: String
    /// 이 배포가 쓴 빌드 (서버 #36). "다시 시도"가 같은 빌드로 새 배포를 만들 때 써요
    let sourceVersionId: String?
    let image: String?
    /// 웹 W-09 "버전" 열 (가칭): "v7"
    let version: String?
    /// 웹 실행 목록의 커밋 메시지 (가칭)
    let commitMessage: String?
    let state: DeploymentState
    let targets: [Target]?
    let pendingApproval: PendingApproval?
    /// 환경별 승인 대기 ID `[{ target_id, approval_id }]` (10/2 00:40 서버 확정, A-04). 승인 요청 `items`에 그대로 담아요
    let pendingApprovals: [ApprovalItem]?
    let createdBy: String?
    let createdAt: Date?
    let finishedAt: Date?
    /// 롤백도 배포 한 건이에요: `kind: "rollback"`, `rolled_back_from` (WR-14)
    let kind: String?
    let rolledBackFrom: String?
    /// 이 배포의 AI 사용량 합계 (예비). 10/1 서버 결정으로 W-12 합계는 plan(A-05), 호출 기록은 ai-usage 목록이 기준이고, 이 값은 그게 없을 때만 써요
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

    /// 요약(A-05)에 상세(WR-06)의 리소스 행 · plan 원문을 환경별로 붙여요. 상세에 없는 값은 요약 것을 그대로 둬요
    func merging(_ details: [PlanDetail]) -> Plan {
        Plan(deploymentId: deploymentId, targets: targets.map { target in
            guard let detail = details.first(where: { $0.targetId == target.targetId }) else { return target }
            return Target(targetId: target.targetId, counts: target.counts, hasDelete: target.hasDelete, risks: target.risks,
                          reusedScript: target.reusedScript, resources: detail.resources ?? target.resources,
                          summary: target.summary, planText: detail.planText ?? target.planText)
        }, aiUsage: aiUsage)
    }
}

/// WR-06 plan 상세 한 환경: `GET /deployments/{id}/plan?detail=resources` 배열의 원소 (서버 #51)
struct PlanDetail: Decodable, Sendable {
    let targetId: String
    let resources: [PlanResource]?
    let planText: String?
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
    /// 토큰을 확인하지 못한 호출 수 (A-05 `unknown_calls`). 0보다 크면 토큰 합계는 "일부"예요
    let unknownCalls: Int?
    let items: [Call]?
}

enum ApprovalDecision: String, Encodable, Sendable {
    case approve, reject
}

// MARK: - 커밋 · 파이프라인 (A-06)

/// `queued`: 빌드가 접수됐지만 아직 시작 전 (서버 #38, 웹 W-03 "대기 중")
enum PipelineStatus: String, ServerEnum {
    case queued, running, success, failed, unknown
    static let unknownCase = PipelineStatus.unknown
}

struct Build: Decodable, Identifiable, Hashable, Sendable {
    struct Pipeline: Decodable, Hashable, Sendable {
        let status: PipelineStatus
        let runUrl: URL?

        private enum CodingKeys: String, CodingKey { case status, runUrl }

        /// 서버는 상태를 모르면 null을 줘요 (#38) → 알 수 없음
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            status = try c.decodeIfPresent(PipelineStatus.self, forKey: .status) ?? .unknown
            runUrl = try c.decodeIfPresent(URL.self, forKey: .runUrl)
        }
    }

    struct DeployedTarget: Decodable, Hashable, Sendable {
        let targetId: String
        let deploymentId: String
        let deployedAt: Date?
    }

    /// 빌드 한 건의 ID (#38). 같은 커밋을 다시 빌드하면 ID가 달라요. 배포 시작은 이 ID로 골라요 (#36)
    let sourceVersionId: String?
    let commit: String
    /// 커밋 메시지 · 작성자 · 시각은 서버가 아직 주지 않아요 (#38 "미제공") → 화면은 "—"
    let message: String?
    let author: String?
    let committedAt: Date?
    let pipeline: Pipeline
    let image: String?
    let deployedTo: [DeployedTarget]?
    /// W-03 이미지 카드 · 단계 (가칭)
    let branch: String?
    /// 서비스가 하나면 이미지 digest, 둘 이상이면 null (#38)
    let imageDigest: String?
    let steps: [StepItem]?

    var id: String { sourceVersionId ?? commit }
}

// MARK: - 인증 (R-02)

struct AuthToken: Decodable, Sendable {
    let accessToken: String
    let expiresAt: Date?
    let role: String

    /// 데모 읽기 전용 계정 (R-03). 승인하면 403이 와요.
    var isViewer: Bool { role == "viewer" }
}

extension Deployment {
    /// 승인 요청에 실을 항목: 화면에서 승인 대기로 보여준 환경마다 `approval_id`.
    /// 서버는 A-04 `pending_approvals`로만 줘요 (10/2 00:40 #40 답). 못 찾은 환경은 빼고, 비면 화면이 요청을 막아요 (빈 `items`는 400)
    func approvalItems(for targetIDs: [String]) -> [ApprovalItem] {
        targetIDs.compactMap { id in pendingApprovals?.first { $0.targetId == id } }
    }

    /// 사람이 승인 · 거절해야 하는 배포예요: 승인 대기이고, 아직 승인하지 않은 환경이 하나라도 있어요
    /// (승인 완료 · 실행 대기 환경만 남았으면 아니에요, 웹 #64와 같아요). 환경 목록이 없으면 `pending_approvals`로 봐요.
    /// 사이드바 배지 · iPhone 빨간 점은 프로젝트의 가장 최근 배포(A-03 첫 건)에만 이 규칙을 써요 (`Workspace.actionableApproval`)
    var needsDecision: Bool {
        guard state == .awaitingApproval else { return false }
        guard let targets, !targets.isEmpty else { return pendingApprovals?.isEmpty == false }
        return targets.contains { $0.resolvedState == .awaitingApproval && !$0.isApprovedWaiting }
    }
}

/// 배포를 만든 응답 (배포 시작 · 다시 시도 · 롤백): `{ id, project_id, state }` (10/2 01:07 서버 #42). 나머지는 A-04로 다시 읽어요
struct CreatedDeployment: Decodable, Sendable {
    let id: String
    let projectId: String?
    let state: DeploymentState?
}
