import Foundation

// 웹 와이어프레임(W-00~W-13)을 앱에 옮기면서 필요해진 응답 모양. 전부 (가칭)이고,
// 서버 OpenAPI가 나오면 맞춰요. SPEC §6-8과 1:1.

/// 단계 한 줄 (웹 Step Item): 라벨 · 상태 · 걸린 시간.
struct StepItem: Decodable, Hashable, Sendable {
    let name: String
    let state: StepState
    let durationMs: Int?
    let startedAt: Date?
}

/// W-06 plan 리소스 변경 행: `+ aws_ecs_service.web +₩18,000/월`.
struct PlanResource: Decodable, Hashable, Sendable {
    enum Action: String, ServerEnum {
        case create, update, delete, unknown
        static let unknownCase = Action.unknown
    }

    let action: Action
    let address: String
    let monthlyCostKrw: Int?
}

/// W-01 · W-08 동일성 검증 표.
struct Parity: Decodable, Sendable {
    struct Row: Decodable, Identifiable, Sendable {
        struct Cell: Decodable, Hashable, Sendable {
            let targetId: String
            let value: String?
            let ok: Bool
        }

        /// digest · commit · app_version · health · env_hash
        let key: String
        let cells: [Cell]
        var id: String { key }
    }

    let targets: [String]
    let rows: [Row]
    let matching: Int
    let total: Int
}

/// W-04 · W-10 대상 환경.
struct DeployTarget: Decodable, Identifiable, Hashable, Sendable {
    let id: String
    let type: TargetType
    let name: String
    /// "온프레미스 · Docker Compose", "AWS · ECS + ALB"
    let title: String?
    /// 유형: "Proxmox VM · Docker Compose"
    let runtime: String?
    /// 위치(온프레미스) 또는 리전(클라우드)
    let location: String?
    /// 연결: "사설망(VPN) + SSH", "IAM 역할"
    let connection: String?
    /// 공개: "팀 도메인 HTTPS"
    let exposure: String?
    /// state 저장소. 없으면 [미정]
    let stateBackend: String?
    let currentCommit: String?
    let connected: Bool?
    let health: Health?
    /// 이 환경에 검증된 스크립트가 있으면 재사용 (W-04 카드 설명)
    let hasVerifiedScript: Bool?
}

struct ConnectionTestResult: Decodable, Sendable {
    let connected: Bool
    let message: String?
}

struct EnvironmentResource: Decodable, Hashable, Sendable {
    let address: String
    let type: String?
}

/// W-02 저장소 확인 결과 (배포 명세 확인 카드).
struct RepositoryInspection: Decodable, Sendable {
    let branches: [String]
    let dockerfile: Bool
    let deployYaml: Bool
    let port: Int?
    let healthcheck: String?
    let env: [String]
    let database: Bool?
}

/// W-11 검증된 스크립트.
struct Script: Decodable, Identifiable, Hashable, Sendable {
    enum Outcome: String, ServerEnum {
        case passed, discarded, unknown
        static let unknownCase = Outcome.unknown
    }

    let id: String
    let targetId: String
    let targetType: TargetType
    /// "s2"
    let version: String
    let attempt: Int
    let outcome: Outcome
    /// "보안 그룹 수정" 같은 한 줄
    let note: String?
    /// "validate · plan · 위험 0" / "plan 실패"
    let checks: String?
    let reuseCount: Int?
    let lastUsedAt: Date?
    /// "aws/main.tf"
    let file: String?
    let content: String?
    let baseCommit: String?
    let input: String?
    let aiTokens: Int?
    let storage: String?
    let createdAt: Date?
}

/// W-12 AI 사용량.
struct AIUsageReport: Decodable, Sendable {
    struct Call: Decodable, Identifiable, Hashable, Sendable {
        let id: String
        let at: Date?
        let targetType: TargetType
        let task: String
        let attempt: Int?
        let tokens: Int
        let costKrw: Int?
        let result: String
        let ok: Bool?
    }

    let calls: Int
    let tokens: Int
    let costKrw: Int?
    let savedCalls: Int
    let history: [Call]
}

/// W-13 프로젝트 설정.
struct ProjectSettings: Decodable, Sendable {
    let repository: String?
    let branch: String?
    let build: String?
    let registry: String?
    let webhookLastAt: Date?
    let deployYamlRef: String?
    let deployYaml: String?
    let secrets: [String]
}

/// 로그 한 줄 (A-07, SSE log.batch와 같은 모양).
struct LogLine: Decodable, Hashable, Sendable {
    let ts: Date?
    let targetId: String?
    let level: String
    let text: String
}
