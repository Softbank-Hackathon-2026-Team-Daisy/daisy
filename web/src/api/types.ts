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
}

export type AiUsageSummary = {
  calls: number
  tokens: number
  cost_krw: number
  exchange_rate: number
  estimated: boolean
}

export type AiUsageItem = {
  at: string
  target_id: string
  step: 'generate' | 'fix'
  title: string
  attempt: number
  tokens: number
  cost_krw: number
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
  ai_usage?: { summary: AiUsageSummary; items: AiUsageItem[] }
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
  resources: { address: string; action: 'create' | 'update' | 'delete' | 'replace' }[]
  plan_text: string
}

// A-06 GET /projects/{id}/builds
export type Build = {
  commit: string
  message: string
  author: string
  committed_at: string
  pipeline: { status: 'running' | 'success' | 'failed'; run_url: string; steps?: { name: string; state: 'running' | 'done' | 'failed' | 'waiting' }[] }
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
}

// WR-03
export type Manifest = {
  ref: string
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
