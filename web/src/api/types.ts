// 서버 응답 모양 — SPEC.md §6-4 (공용 모델은 ios/SPEC.md §6-7). 서버 OpenAPI가 나오면 맞춰요 (가칭)
// JSON 키는 서버의 snake_case 그대로 써요. 상태 값은 SPEC.md §2-5 (9/30 서버 확정)

export type EnvKind = 'onprem' | 'aws' | 'gcp'

export type DeploymentState =
  | 'queued'
  | 'running'
  | 'awaiting_approval'
  | 'succeeded'
  | 'partially_succeeded'
  | 'failed'
  | 'cancelled'

export type TargetState =
  | 'waiting'
  | 'generating'
  | 'validating'
  | 'awaiting_approval'
  | 'applying'
  | 'verifying'
  | 'succeeded'
  | 'failed'
  | 'cancelled'

export type Step = 'generate' | 'validate' | 'plan' | 'risk_check' | 'apply' | 'health_check'

export type Health = 'healthy' | 'unhealthy' | 'unknown'

// A-01 목록 · A-12 상세 (#38). repository_url · manifest_path는 상세에서만 와요
export type Project = {
  id: string
  name: string
  repository: string // "org/repo"
  default_branch: string | null
  repository_url?: string | null
  manifest_path?: string | null
  created_at?: string
  // #13 요청 — 서버 미제공(10/1 #13 답). 목업에만 있어요
  build?: string
  registry?: string
  webhook_last_at?: string
}

// GET /auth/me (#38)
export type Me = { account_id: string; username: string; role: Role }

// A-02 GET /projects/{id}/targets/status — { items, next_cursor } 봉투 (#38)
// current가 null이면 "확인된 현재 배포 없음"이에요. 배포를 한 번도 안 했다는 뜻이 아니에요 (#42, 10/2)
// url · health_summary · image_digest는 인프라 apply 결과가 들어오기 전까지 null, health는 unknown
// WR-04 connection.state와 같은 값 (#42, 10/2에 connected · disconnected에서 바뀜)
export type ConnectionState = 'ok' | 'failed' | 'unknown'
export type TargetStatus = {
  target_id: string
  type: EnvKind
  name: string
  connection_state?: ConnectionState // #38에서 추가. W-04에서 연결 안 되는 환경을 막을 때 써요
  checked_at: string | null
  current: { commit: string; image: string | null; deployment_id: string; deployed_at: string } | null
  current_status?: 'confirmed' | 'unverified' | 'none' // current는 confirmed일 때만 와요 (#42)
  image_digest?: string | null // WR-09
  url: string | null
  health: Health
  health_summary?: string | null // 예: "200 OK · 120ms" — 헬스체크 1회 측정이라 p95는 없어요 (#17 인프라 답)
}

// WR-04 GET /projects/{id}/targets
export type Target = {
  target_id: string
  type: EnvKind
  name: string
  title?: string // 예: "ECS Fargate · ap-northeast-2"
  // WR-04 (#42): { items, next_cursor } 봉투. reuse는 인프라 보고가 없으면 null, 한 번도 확인 안 했으면 checked_at null
  reuse: { available: boolean; script_id?: string; reason?: string } | null
  connection: { state: 'ok' | 'failed' | 'unknown'; checked_at: string | null }
  // W-10 정보 (#13 가칭 선택 필드)
  runtime?: string
  location?: string
  location_label?: '위치' | '리전'
  access_method?: string
  exposure?: string
  state_backend?: string | null // 예: "S3 (잠금)" · "GCS (잠금)" — 서버가 준 이름 그대로 (#17). 온프레미스는 미정
  current_commit?: string | null
}

// A-04 대상 (#46). step · step_state · url · 헬스는 Jenkins 결과 수신(#35) 전까지 null, 생성 전이면 attempt null
export type DeploymentTarget = {
  target_id: string
  type: EnvKind
  name?: string
  state: TargetState
  step: Step | null
  step_state?: string | null
  attempt: number | null // 첫 생성을 포함한 총 시도 횟수 (1~3). 화면에는 "시도 n/3", 없으면 "—"
  reused_script: boolean
  url: string | null
  image_digest?: string | null
  error_summary: string | null
  cancel_requested_at?: string | null
  started_at?: string | null
  finished_at?: string | null
  // 아래는 앱 요청 #13의 선택 필드 (가칭). 없으면 화면이 단계 · 상태에서 추정해요
  title?: string // 예: "ap-northeast-2 · ECS Fargate"
  // skipped = 실행하지 않은 단계 (Jenkins NOT_EXECUTED). 서버가 넘길 값 이름은 은현 님과 맞춰요 (가칭)
  steps?: { name: string; state: 'waiting' | 'running' | 'done' | 'failed' | 'skipped'; duration_ms?: number }[]
  health_summary?: string | null // 예: "200 OK · 120ms" (1회 측정, #17)
}

// AI 사용량 합계는 A-05 plan 응답에 같이 와요 (#13, 10/1 서버 결정). 확인 못 한 토큰 · 비용은 null
export type AiUsageSummary = {
  calls: number
  tokens: number | null
  cost_krw: number | null
  exchange_rate: number | null // 서버 환율 설정이 없으면 null (#51)
  estimated: boolean
  unknown_calls?: number // 토큰 · 비용을 모르는 호출 수 (#51)
}

// GET /projects/{id}/ai-usage?deployment_id= 호출별 기록 (#13, 경로 · 필드는 OpenAPI가 나오면 맞춰요)
// status는 LLM 호출의 성공 · 실패예요 (Terraform 검증 결과가 아니에요). title은 제공 약속이 없어서 선택
export type AiUsageItem = {
  at: string
  target_id: string
  step: 'generate' | 'fix'
  title?: string
  attempt: number
  tokens: number | null
  cost_krw: number | null
  status: 'succeeded' | 'failed'
}

// A-03 목록 · A-04 상세 — 같은 모양 (#46 · #48)
export type Deployment = {
  id: string
  project_id: string
  kind: 'deploy' | 'rollback' | null // 서버는 롤백만 "rollback", 나머지 null
  rolled_back_from: string | null
  retry_of?: string | null
  version?: string // 서버 미제공(후순위) — 화면은 짧은 커밋으로 대신 (versionLabel)
  commit: string
  source_version_id?: string // 다시 시도 · 롤백 때 같은 빌드를 고르려고 (#36)
  commit_message?: string
  image: string | null
  image_digest?: string | null
  images?: { service: string; image_ref: string | null; image_digest: string | null }[] | null
  state: DeploymentState
  targets: DeploymentTarget[]
  // 승인 대기 환경별 승인 ID — 승인 요청 items에 그대로 담아요. 만료된 승인은 빠져요 (#46)
  pending_approvals: { target_id: string; approval_id: string }[]
  created_by: string
  created_at: string
  finished_at: string | null
  last_seq: number
}

// 배포 생성 · 승인 · 취소 · 재시도 · 롤백 응답 (#42). 화면은 id로 다음 화면에 가요
export type DeploymentAccepted = { id: string; project_id: string; state: DeploymentState }

export type Risk = { level: 'high' | 'medium' | 'low'; rule: string; resource: string; message: string }

// A-05 GET /deployments/{id}/plan (#51). 현재 plan이 없는 대상은 targets에서 빠져요
export type Plan = {
  deployment_id: string
  targets: {
    target_id: string
    counts: { create: number; update: number; delete: number }
    has_delete: boolean
    risks: Risk[]
    summary?: string | null // 예: "이미지 태그만 교체". 서버는 원천이 없어 null (#51)
    plan_text?: string | null
  }[]
  ai_usage: AiUsageSummary
}

// WR-06 GET /deployments/{id}/plan?detail=resources
export type PlanDetail = {
  target_id: string
  resources: { address: string; action: 'create' | 'update' | 'delete' | 'replace'; monthly_cost_krw?: number }[]
  // plan 원문 — 비밀값 처리 때문에 제공 여부 미정(승환 님, #9). 없으면 화면이 리소스 목록만 보여줘요
  plan_text?: string
}

// A-06 GET /projects/{id}/builds — 커서 봉투 (#38). 커밋 메시지 · 작성자 · 커밋 시각은 서버 미제공(후순위) → "—"
// 배포 시작은 commit이 아니라 source_version_id로 빌드를 골라요 (#19 · #36)
export type BuildStatus = 'queued' | 'running' | 'success' | 'failed'
export type Build = {
  source_version_id?: string
  commit: string
  branch?: string | null
  message?: string | null
  author?: string | null
  committed_at?: string | null
  received_at?: string | null
  started_at?: string | null
  finished_at?: string | null
  error_summary?: string | null
  // Jenkins 화면은 외부 비공개라 run_url은 화면에서 쓰지 않아요 (#17). 단계는 Checkout → Test → Build & Push → Trigger CD
  // Trigger CD는 운영에서 늘 건너뜀(skipped) — 서버가 CI 결과를 받아 daisy-cd-plan을 직접 시작해요 (#25 채준 님)
  pipeline: { status: BuildStatus | null; run_url?: string | null; steps?: { name: string; state: 'running' | 'done' | 'failed' | 'waiting' | 'skipped'; duration_ms?: number }[] }
  // 서비스가 하나면 image · image_digest, 여럿이면 둘 다 null이고 images[] (#38)
  image: string | null
  image_digest?: string | null
  images?: { service: string; image_ref: string | null; image_digest: string | null }[] | null
  deployed_to: { target_id: string; deployment_id: string; deployed_at: string }[] | null
}

// WR-07 · WR-10
export type Script = {
  script_id: string
  target_id: string
  type: EnvKind
  version: string
  origin: 'ai_generated' | 'reused'
  attempt: number
  note?: string
  validation: { validate: boolean; plan: boolean; risks: number }
  status: 'verified' | 'discarded'
  reuse_count: number
  last_used_at: string
  files?: { path: string; content: string }[]
  // W-11 정보 카드 (#13 가칭 선택 필드)
  base_commit?: string
  input?: string
  ai_tokens?: number
  storage?: string | null
  created_at?: string
}

// WR-03
export type Manifest = {
  ref: string
  raw?: string // 원문 (#13 가칭)
  port: number
  healthcheck: string
  env: string[]
  secrets: string[]
  database: boolean
  errors: string[]
}

export type LogLine = { seq: number; at: string; target_id: string; level: 'INFO' | 'WARN' | 'ERROR'; message: string }

// R-02 POST /auth/token — 역할은 owner · viewer (#32 · #38)
export type Role = 'owner' | 'viewer'
export type AuthToken = { access_token: string; expires_at: string; role: Role }

export type ListResponse<T> = { items: T[]; next_cursor: string | null }
