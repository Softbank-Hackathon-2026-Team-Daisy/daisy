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

/// W-01 · W-08 동일성 검증 표. 서버 API 없이 앱이 만들어요. 규칙은 웹 `ParityTable`과 같아요:
/// 기준은 첫 번째 환경(W-01은 배포된 첫 환경, W-08은 성공한 첫 환경), 기준과 다른 값만 ✗, 값이 없으면 "—".
struct Parity: Sendable {
    struct Row: Identifiable, Sendable {
        struct Cell: Hashable, Sendable {
            let targetId: String
            let value: String?
            /// 기준과 다르거나 실패한 칸
            let failed: Bool
            var ok: Bool { value != nil && !failed }
        }

        /// digest · commit · version · health
        let key: String
        let cells: [Cell]
        var id: String { key }
    }

    let targets: [String]
    let rows: [Row]
    /// 기준 환경과 image digest가 같은 환경 수 (웹 "3/3 일치")
    let matching: Int
    var total: Int { targets.count }

    /// W-01 개요: 환경별 현재 상태(A-02)
    init(statuses: [TargetStatus]) {
        let base = statuses.first { $0.current != nil }
        targets = statuses.map(\.targetId)
        matching = statuses.parityMatching
        func row(_ key: String, _ pick: (TargetStatus) -> String?) -> Row {
            Row(key: key, cells: statuses.map { status in
                let value = pick(status)
                return Row.Cell(targetId: status.targetId, value: value,
                                failed: base != nil && value != nil && value != pick(base!))
            })
        }
        rows = [
            row("digest") { $0.imageDigest },
            row("commit") { $0.current.map { String($0.commit.prefix(7)) } },
            // 웹: 헬스 요약이 있으면 그대로, 없으면 "정상" · "실패"
            Row(key: "health", cells: statuses.map {
                Row.Cell(targetId: $0.targetId,
                         value: $0.healthSummary ?? ($0.health == .healthy ? "정상" : $0.health == .unhealthy ? "실패" : nil),
                         failed: $0.health == .unhealthy)
            }),
        ]
    }

    /// W-08 결과: 이 배포의 환경별 결과(A-04). 성공한 환경끼리 비교해요
    init(deployment: Deployment) {
        let all = deployment.targets ?? []
        let base = all.first { $0.state == .succeeded }
        targets = all.map(\.targetId)
        matching = all.filter { $0.state == .succeeded && $0.imageDigest != nil && $0.imageDigest == base?.imageDigest }.count
        let commit = String(deployment.commit.prefix(7))
        rows = [
            Row(key: "digest", cells: all.map {
                Row.Cell(targetId: $0.targetId, value: $0.imageDigest,
                         failed: base != nil && $0.imageDigest != nil && $0.imageDigest != base?.imageDigest)
            }),
            Row(key: "commit", cells: all.map { Row.Cell(targetId: $0.targetId, value: commit, failed: false) }),
            Row(key: "version", cells: all.map { Row.Cell(targetId: $0.targetId, value: deployment.version, failed: false) }),
            // 웹: 성공은 헬스 요약 그대로("200 OK · 120ms", 없으면 "—"), 실패는 요약 또는 "실패"
            Row(key: "health", cells: all.map {
                Row.Cell(targetId: $0.targetId,
                         value: $0.state == .succeeded ? ($0.healthSummary ?? "—") : $0.state == .failed ? ($0.healthSummary ?? "실패") : nil,
                         failed: $0.state == .failed)
            }),
        ]
    }
}

extension DeployTarget {
    /// 연결 테스트가 실패한 환경은 W-04에서 고를 수 없어요 (웹과 같아요)
    var isUnreachable: Bool { connection?.state == .failed }
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
    /// 위 값의 라벨: "위치" · "리전" (웹 `location_label`)
    let locationLabel: String?
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
    /// 검증 오류 한 줄. 웹 목업은 문자열 배열, 앱 초안은 `{path, message}`라 둘 다 받아요 (서버 OpenAPI 대기)
    struct Problem: Decodable, Hashable, Sendable {
        let path: String?
        let message: String

        init(from decoder: Decoder) throws {
            if let text = try? decoder.singleValueContainer().decode(String.self) {
                path = nil; message = text
                return
            }
            let container = try decoder.container(keyedBy: CodingKeys.self)
            path = try container.decodeIfPresent(String.self, forKey: .path)
            message = try container.decode(String.self, forKey: .message)
        }

        private enum CodingKeys: String, CodingKey { case path, message }
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
    /// 서버는 모르면 null을 줘요 (#68)
    let origin: Origin?
    /// 통과한 시도 (n/3). 시도 0(생성 전)이면 null이에요 (#68)
    let attempt: Int?
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
/// 로그 한 줄. 앱 초안은 `ts` · `text`, 웹 목업은 `at` · `message` · `seq`라 둘 다 받아요 (서버 OpenAPI 대기)
struct LogLine: Decodable, Hashable, Sendable {
    let ts: Date?
    let targetId: String?
    let level: String
    let text: String

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        ts = try c.decodeIfPresent(Date.self, forKey: .ts) ?? c.decodeIfPresent(Date.self, forKey: .at)
        targetId = try c.decodeIfPresent(String.self, forKey: .targetId)
        level = try c.decodeIfPresent(String.self, forKey: .level) ?? "info"
        text = try c.decodeIfPresent(String.self, forKey: .text) ?? c.decodeIfPresent(String.self, forKey: .message) ?? ""
    }

    private enum CodingKeys: String, CodingKey { case ts, at, targetId, level, text, message }
}

/// WR-02 연결 응답 `{ project, manifest }` (서버 #59). `manifest`가 null이면 "검증 전"이에요
struct ConnectResult: Decodable, Sendable {
    let project: Project
    let manifest: Manifest?
}
