import Foundation

// 웹 와이어프레임(W-00~W-13)을 앱에 옮기면서 쓰는 응답 모양.
// 웹과 같은 API는 `web/SPEC.md` WR-xx 모양을 따르고(9/30 서버 답변), 앱이 더 요청한 것만 (가칭)이에요. SPEC §6-8과 1:1.

/// 단계 한 줄 (웹 Step Item): 라벨 · 상태 · 걸린 시간. (가칭, §6-8 필드 추가)
struct StepItem: Decodable, Hashable, Sendable {
    let name: String
    let state: StepState
    let durationMs: Int?
    let startedAt: Date?
}

/// WR-06 plan 리소스 행: `+ aws_ecs_service.web`.
struct PlanResource: Decodable, Hashable, Sendable {
    enum Action: String, ServerEnum {
        case create, update, delete, replace, unknown
        static let unknownCase = Action.unknown
    }

    let action: Action
    let address: String
    /// 인프라 월 비용은 서버에서 보류예요. 오면 보여줘요.
    let monthlyCostKrw: Int?
}

/// W-01 · W-08 동일성 검증 표. 서버 API 없이 A-02(`image_digest` · 커밋 · 헬스)로 앱이 만들어요.
struct Parity: Sendable {
    struct Row: Identifiable, Sendable {
        struct Cell: Hashable, Sendable {
            let targetId: String
            let value: String?
            let ok: Bool
        }

        /// digest · commit · health
        let key: String
        let cells: [Cell]
        var id: String { key }
    }

    let targets: [String]
    let rows: [Row]

    /// 모든 항목이 맞는 환경 수 (웹 "3/3 일치"와 같은 기준: 환경 단위)
    var matching: Int {
        targets.filter { id in rows.allSatisfy { row in row.cells.first { $0.targetId == id }?.ok == true } }.count
    }
    var total: Int { targets.count }

    init(statuses: [TargetStatus]) {
        targets = statuses.map(\.targetId)
        func row(_ key: String, _ value: (TargetStatus) -> String?) -> Row {
            let values = statuses.map(value)
            // 가장 많은 환경이 가진 값이 기준이에요
            let counts = Dictionary(values.compactMap { $0 }.map { ($0, 1) }, uniquingKeysWith: +)
            let majority = counts.max { $0.value < $1.value }?.key
            return Row(key: key, cells: zip(statuses, values).map { status, value in
                Row.Cell(targetId: status.targetId, value: value, ok: value != nil && value == majority)
            })
        }
        rows = [
            row("digest") { $0.imageDigest.map { String($0.prefix(19)) } },
            row("commit") { $0.current.map { String($0.commit.prefix(7)) } },
            Row(key: "health", cells: statuses.map {
                Row.Cell(targetId: $0.targetId, value: $0.health == .healthy ? "정상" : $0.health == .unhealthy ? "이상" : nil,
                         ok: $0.health == .healthy)
            }),
        ]
    }
}

/// WR-04 · W-04 · W-10 대상 환경 (`GET /projects/{id}/targets`).
struct DeployTarget: Decodable, Identifiable, Hashable, Sendable {
    struct Reuse: Decodable, Hashable, Sendable {
        let available: Bool
        let scriptId: String?
        /// "검증된 스크립트 s3이 있어요"
        let reason: String?
    }

    struct Connection: Decodable, Hashable, Sendable {
        enum State: String, ServerEnum {
            case ok, failed, unknown
            static let unknownCase = State.unknown
        }

        let state: State
        let checkedAt: Date?
    }

    let targetId: String
    let type: TargetType
    let name: String
    let reuse: Reuse?
    let connection: Connection?

    // W-10 인프라 구성 줄 (가칭, §6-8 필드 추가)
    /// "온프레미스 · Docker Compose", "AWS · ECS + ALB"
    let title: String?
    /// 유형: "Proxmox VM · Docker Compose"
    let runtime: String?
    /// 위치(온프레미스) 또는 리전(클라우드)
    let location: String?
    /// 연결 방식: "사설망(VPN) + SSH", "IAM 역할"
    let accessMethod: String?
    /// 공개: "팀 도메인 HTTPS"
    let exposure: String?
    /// state 저장소. 없으면 [미정]
    let stateBackend: String?
    let currentCommit: String?

    var id: String { targetId }
}

/// W-10 "연결 테스트" (가칭 A-10)
struct ConnectionTestResult: Decodable, Sendable {
    let connected: Bool
    let message: String?
}

/// W-10 "리소스 보기" (가칭 A-11)
struct EnvironmentResource: Decodable, Hashable, Sendable {
    let address: String
    let type: String?
}

/// WR-03 파싱된 `deploy.yaml`과 검증 오류 (스키마는 팀 결정 대기).
struct Manifest: Decodable, Sendable {
    struct Problem: Decodable, Hashable, Sendable {
        let path: String?
        let message: String
    }

    let port: Int?
    let healthcheck: String?
    let env: [String]?
    let secrets: [String]?
    let database: Bool?
    let errors: [Problem]?
    /// 원문 (가칭, W-13 코드 블록)
    let raw: String?
    /// "deploy.yaml · main@a1b2c3d" (가칭)
    let ref: String?
}

/// 프로젝트 상세 (`GET /projects/{id}`, 노션 계약 v0.2 3-2 제안). W-13 저장소 카드.
struct ProjectDetail: Decodable, Sendable {
    let id: String
    let name: String
    let repository: String?
    let branch: String?
    // (가칭, §6-8 필드 추가)
    let build: String?
    let registry: String?
    let webhookLastAt: Date?
}

/// WR-07 · WR-10 스크립트.
struct Script: Decodable, Identifiable, Hashable, Sendable {
    enum Origin: String, ServerEnum {
        case aiGenerated = "ai_generated"
        case reused, unknown
        static let unknownCase = Origin.unknown
    }

    enum Status: String, ServerEnum {
        case verified, discarded, unknown
        static let unknownCase = Status.unknown
    }

    struct Validation: Decodable, Hashable, Sendable {
        let validate: Bool?
        let plan: Bool?
        let risks: Int?
    }

    struct File: Decodable, Hashable, Sendable {
        let path: String
        let content: String
    }

    let scriptId: String
    let targetId: String
    /// "s2"
    let version: String
    let origin: Origin
    /// 통과한 시도 (n/3)
    let attempt: Int
    let validation: Validation?
    let status: Status
    let reuseCount: Int?
    let lastUsedAt: Date?
    /// WR-07에서만 와요
    let files: [File]?

    // W-11 정보 카드 (가칭, §6-8 필드 추가)
    /// "보안 그룹 수정" 같은 한 줄
    let note: String?
    let baseCommit: String?
    let input: String?
    let aiTokens: Int?
    let storage: String?
    let createdAt: Date?

    var id: String { scriptId }
}

/// 로그 한 줄 (A-07, SSE log.batch와 같은 모양).
struct LogLine: Decodable, Hashable, Sendable {
    let ts: Date?
    let targetId: String?
    let level: String
    let text: String
}
