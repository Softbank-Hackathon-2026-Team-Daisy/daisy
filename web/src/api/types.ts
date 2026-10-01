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

export type Project = {
  id: string
  name: string
  repository: string
  branch?: string
  // A-12 GET /projects/{id} (#13 가칭) 선택 필드
  build?: string
  registry?: string
  webhook_last_at?: string
}

// A-02 GET /projects/{id}/targets/status
export type TargetStatus = {
  target_id: string
  type: EnvKind
  name: string
  current: { commit: string; image: string; deployment_id: string; deployed_at: string } | null
  image_digest?: string // WR-09
  url: string | null
  health: Health
  health_summary?: string // 예: "200 OK · 120ms" — 헬스체크 1회 측정이라 p95는 없어요 (#17 인프라 답). 없으면 상태만 보여줘요
  checked_at: string
}

// WR-04 GET /projects/{id}/targets
export type Target = {
  target_id: string
  type: EnvKind
  name: string
  title?: string // 예: "ECS Fargate · ap-northeast-2"
  reuse: { available: boolean; script_id?: string; reason?: string }
  connection: { state: 'ok' | 'failed' | 'unknown'; checked_at: string }
  // W-10 정보 (#13 가칭 선택 필드)
  runtime?: string
  location?: string
  location_label?: '위치' | '리전'
  access_method?: string
  exposure?: string
  state_backend?: string | null // 예: "S3 (잠금)" · "GCS (잠금)" — 서버가 준 이름 그대로 (#17). 온프레미스는 미정
  current_commit?: string | null
}

export type DeploymentTarget = {
  target_id: string
  type: EnvKind
  state: TargetState
  step: Step
  attempt: number // 첫 생성을 포함한 총 시도 횟수 (1~3). 화면에는 "시도 n/3"
  reused_script: boolean
  url: string | null
  image_digest?: string
  error_summary: string | null
  // 아래는 앱 요청 #13의 선택 필드 (가칭). 없으면 화면이 단계 · 상태에서 추정해요
  title?: string // 예: "ap-northeast-2 · ECS Fargate"
  // skipped = 실행하지 않은 단계 (Jenkins NOT_EXECUTED). 서버가 넘길 값 이름은 은현 님과 맞춰요 (가칭)
  steps?: { name: string; state: 'waiting' | 'running' | 'done' | 'failed' | 'skipped'; duration_ms?: number }[]
  health_summary?: string // 예: "200 OK · 120ms" (1회 측정, #17)
}

// AI 사용량 합계는 A-05 plan 응답에 같이 와요 (#13, 10/1 서버 결정). 확인 못 한 토큰 · 비용은 null
export type AiUsageSummary = {
  calls: number
  tokens: number | null
  cost_krw: number | null
  exchange_rate: number
  estimated: boolean
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

// A-03 목록(요약) · A-04 스냅샷(전체)
export type Deployment = {
  id: string
  project_id: string
  kind: 'deploy' | 'rollback'
  rolled_back_from: string | null
  version: string
  commit: string
  commit_message?: string
  image: string
  state: DeploymentState
  targets: DeploymentTarget[]
  pending_approval: { approval_id: string; kind: 'plan' } | null
  created_by: string
  created_at: string
  finished_at: string | null
  last_seq: number
}

export type Risk = { level: 'high' | 'medium' | 'low'; rule: string; resource: string; message: string }

// A-05 GET /deployments/{id}/plan
export type Plan = {
  deployment_id: string
  targets: {
    target_id: string
    counts: { create: number; update: number; delete: number }
    has_delete: boolean
    risks: Risk[]
    summary?: string // 예: "이미지 태그만 교체"
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

// A-06 GET /projects/{id}/builds
export type Build = {
  commit: string
  message: string
  author: string
  committed_at: string
  // Jenkins 화면은 외부 비공개라 run_url은 화면에서 쓰지 않아요 (#17). 단계는 Checkout → Test → Build & Push → Trigger CD
  // Trigger CD는 운영에서 늘 건너뜀(skipped) — 서버가 CI 결과를 받아 daisy-cd-plan을 직접 시작해요 (#25 채준 님)
  pipeline: { status: 'running' | 'success' | 'failed'; run_url?: string; steps?: { name: string; state: 'running' | 'done' | 'failed' | 'waiting' | 'skipped'; duration_ms?: number }[] }
  image: string | null
  digest?: string
  deployed_to: { target_id: string; deployment_id: string; deployed_at: string }[]
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

// R-02 POST /auth/token
export type AuthToken = { access_token: string; expires_at: string; role: 'admin' | 'viewer' }

export type ListResponse<T> = { items: T[]; next_cursor: string | null }
