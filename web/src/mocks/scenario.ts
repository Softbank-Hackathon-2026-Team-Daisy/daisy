import type {
  AiUsageItem,
  Build,
  Deployment,
  DeploymentTarget,
  LogLine,
  Manifest,
  Plan,
  PlanDetail,
  Project,
  Script,
  Target,
  TargetStatus,
} from '../api/types.ts'

// MOCK: 와이어프레임 v1.0 예시 값 그대로의 시나리오 (SPEC.md §6-4 모양). 서버가 열리면 지워요
// sample-monolith · 커밋 a1b2c3d · 환경 3개 · AWS 시도 2/3 · GCP 헬스체크 실패 → 일부 성공

const ago = (min: number) => new Date(Date.now() - min * 60_000).toISOString()

export const PROJECT_ID = 'prj_monolith'
export const COMMIT = 'a1b2c3d'
export const IMAGE = `ghcr.io/team-daisy/sample-monolith:${COMMIT}`
export const DIGEST = 'sha256:9f3c…e1a'

export const projects: Project[] = [
  { id: 'prj_monolith', name: 'sample-monolith', repository: 'Softbank-Hackathon-2026-Team-Daisy/sample-monolith', branch: 'main', build: 'GitHub Actions · ci.yml', registry: 'ghcr.io', webhook_last_at: ago(3) },
  { id: 'prj_msa', name: 'sample-msa', repository: 'Softbank-Hackathon-2026-Team-Daisy/sample-msa', branch: 'main' },
]

export const targetStatus: TargetStatus[] = [
  { target_id: 'tgt_onprem', type: 'onprem', name: 'home-lab', current: { commit: COMMIT, image: IMAGE, deployment_id: 'dep_41', deployed_at: ago(12) }, image_digest: DIGEST, url: 'https://sample.home-lab.daisy.dev', health: 'healthy', checked_at: ago(1) },
  { target_id: 'tgt_aws', type: 'aws', name: 'aws-prod', current: { commit: COMMIT, image: IMAGE, deployment_id: 'dep_41', deployed_at: ago(12) }, image_digest: DIGEST, url: 'https://sample-monolith.aws.daisy.dev', health: 'healthy', checked_at: ago(1) },
  { target_id: 'tgt_gcp', type: 'gcp', name: 'gcp-prod', current: { commit: COMMIT, image: IMAGE, deployment_id: 'dep_41', deployed_at: ago(12) }, image_digest: DIGEST, url: 'https://sample-monolith-x7k.a.run.app', health: 'healthy', checked_at: ago(1) },
]

export const targets: Target[] = [
  { target_id: 'tgt_onprem', type: 'onprem', name: 'home-lab', title: '온프레미스 · Docker Compose', runtime: 'Proxmox VM · Docker Compose', location: 'home-lab', location_label: '위치', access_method: '사설망(VPN) + SSH', exposure: '팀 도메인 HTTPS', state_backend: null, current_commit: COMMIT, reuse: { available: true, script_id: 'scr_onprem_s3', reason: 'home-lab Proxmox VM · 사설망 · 검증된 스크립트 있음 → 태그만 교체' }, connection: { state: 'ok', checked_at: ago(1) } },
  { target_id: 'tgt_aws', type: 'aws', name: 'aws-prod', title: 'AWS · ECS + ALB', runtime: 'ECS Fargate + ALB', location: 'ap-northeast-2', location_label: '리전', access_method: 'IAM 역할', exposure: 'ALB · 팀 도메인', state_backend: null, current_commit: COMMIT, reuse: { available: false, reason: 'ap-northeast-2 · 처음 배포 → AI가 Terraform 생성' }, connection: { state: 'ok', checked_at: ago(1) } },
  { target_id: 'tgt_gcp', type: 'gcp', name: 'gcp-prod', title: 'GCP · Cloud Run', runtime: 'Cloud Run', location: 'asia-northeast3', location_label: '리전', access_method: '서비스 계정', exposure: 'run.app 자동 URL', state_backend: null, current_commit: COMMIT, reuse: { available: false, reason: 'asia-northeast3 · 처음 배포 → AI가 Terraform 생성' }, connection: { state: 'ok', checked_at: ago(1) } },
]

export const manifest: Manifest = {
  ref: `deploy.yaml · main@${COMMIT}`,
  port: 8080,
  healthcheck: '/health',
  env: ['LOG_LEVEL', 'SHUTDOWN_TIMEOUT'],
  secrets: [],
  database: false,
  errors: [],
  raw: `name: hellocalc
port: 8080
healthcheck: /health
env:
  - LOG_LEVEL
  - SHUTDOWN_TIMEOUT
secrets: []
database: false`,
}

export const builds: Build[] = [
  {
    commit: COMMIT,
    message: 'feat: 결제 페이지 추가 (#42)',
    author: '도영',
    committed_at: ago(2),
    pipeline: {
      status: 'running',
      run_url: 'https://github.com/Softbank-Hackathon-2026-Team-Daisy/sample-monolith/actions',
      steps: [
        { name: '이미지 빌드', state: 'done', duration_ms: 42000 },
        { name: '이미지 테스트', state: 'done', duration_ms: 42000 },
        { name: '커밋 해시로 태그', state: 'done', duration_ms: 42000 },
        { name: '레지스트리 업로드', state: 'running', duration_ms: 18000 },
      ],
    },
    image: IMAGE,
    digest: 'sha256:9f3c…e21a',
    deployed_to: [],
  },
  { commit: 'f4e5d6c', message: 'fix: 헬스체크 경로 수정 (#41)', author: '도영', committed_at: ago(3), pipeline: { status: 'success', run_url: '#' }, image: 'ghcr.io/team-daisy/sample-monolith:f4e5d6c', deployed_to: [] },
]

const aiItems: AiUsageItem[] = [
  { at: ago(9), target_id: 'tgt_aws', step: 'generate', title: 'Terraform 생성 (deploy.yaml)', attempt: 1, tokens: 3120, cost_krw: 82, status: 'succeeded' },
  { at: ago(9), target_id: 'tgt_aws', step: 'fix', title: '보안 그룹 0.0.0.0/0 수정', attempt: 2, tokens: 1860, cost_krw: 48, status: 'succeeded' },
  { at: ago(10), target_id: 'tgt_gcp', step: 'generate', title: 'Terraform 생성 (deploy.yaml)', attempt: 1, tokens: 2940, cost_krw: 76, status: 'succeeded' },
]

const aiUsage = { summary: { calls: 5, tokens: 7920, cost_krw: 206, exchange_rate: 1400, estimated: true }, items: aiItems }

type TargetPatch = Partial<DeploymentTarget> & Pick<DeploymentTarget, 'state' | 'step'>

function deployment(id: string, state: Deployment['state'], t: [TargetPatch, TargetPatch, TargetPatch], extra: Partial<Deployment> = {}): Deployment {
  const base: DeploymentTarget[] = [
    { target_id: 'tgt_onprem', type: 'onprem', title: 'home-lab · Docker', state: 'waiting', step: 'generate', attempt: 1, reused_script: true, url: null, error_summary: null },
    { target_id: 'tgt_aws', type: 'aws', title: 'ap-northeast-2 · ECS Fargate', state: 'waiting', step: 'generate', attempt: 1, reused_script: false, url: null, error_summary: null },
    { target_id: 'tgt_gcp', type: 'gcp', title: 'asia-northeast3 · Cloud Run', state: 'waiting', step: 'generate', attempt: 1, reused_script: false, url: null, error_summary: null },
  ]
  return {
    id,
    project_id: PROJECT_ID,
    kind: 'deploy',
    rolled_back_from: null,
    version: 'v7',
    commit: COMMIT,
    commit_message: 'feat: 결제 페이지 추가 (#42)',
    image: IMAGE,
    state,
    targets: base.map((b, i) => ({ ...b, ...t[i] })),
    pending_approval: state === 'awaiting_approval' ? { approval_id: 'apv_7', kind: 'plan' } : null,
    created_by: '도영',
    created_at: ago(10),
    finished_at: null,
    ai_usage: aiUsage,
    last_seq: 0,
    ...extra,
  }
}

const URLS = targetStatus.map((t) => t.url)

type StepState = 'waiting' | 'running' | 'done' | 'failed'
const st = (name: string, state: StepState, sec?: number) => ({ name, state, duration_ms: sec === undefined ? undefined : sec * 1000 })
const VALIDATED = [st('스크립트 재사용', 'done', 2), st('terraform validate', 'done', 42), st('terraform plan', 'done', 42), st('위험 설정 검사', 'done', 42)]
const AI_VALIDATED = [st('Terraform 생성 (AI)', 'done', 42), st('terraform validate', 'done', 42), st('terraform plan', 'done', 42), st('위험 설정 검사', 'done', 42)]
const APPLIED = [st('이미지 pull', 'done', 42), st('terraform apply', 'done', 42), st('state 저장', 'done', 42), st('헬스체크', 'done', 42)]
const HEALTHY = '200 OK · p95 120ms'

// 화면별로 고정된 상태 — 경로의 deploymentId로 골라 봐요 (/projects/prj_monolith/deployments/dep_generate/generate 등)
export const deployments: Record<string, Deployment> = {
  // W-05: 온프레미스 통과, AWS 시도 2/3 수정 중, GCP validate 중
  dep_generate: deployment('dep_generate', 'running', [
    { state: 'awaiting_approval', step: 'risk_check', steps: VALIDATED },
    {
      state: 'validating',
      step: 'risk_check',
      attempt: 2,
      error_summary: '보안 그룹에서 0.0.0.0/0으로 DB 포트가 열려요.',
      steps: [
        st('Terraform 생성 (AI)', 'done', 42),
        st('terraform validate', 'done', 42),
        st('terraform plan', 'done', 42),
        st('위험 설정 검사', 'failed', 63),
        st('AI 수정 후 재검증 · 2/3', 'running', 18),
      ],
    },
    { state: 'validating', step: 'validate', steps: [st('Terraform 생성 (AI)', 'done', 42), st('terraform validate', 'running', 18), st('terraform plan', 'waiting'), st('위험 설정 검사', 'waiting')] },
  ]),
  // W-05b: AWS만 3회 실패로 멈춤, 나머지는 계속
  dep_stuck: deployment('dep_stuck', 'awaiting_approval', [
    { state: 'awaiting_approval', step: 'risk_check', steps: VALIDATED },
    {
      state: 'failed',
      step: 'plan',
      attempt: 3,
      error_summary: 'terraform plan 오류: IAM 권한 부족 (ecs:CreateService)',
      steps: [st('시도 1/3 · plan 실패', 'failed', 63), st('시도 2/3 · plan 실패', 'failed', 63), st('시도 3/3 · plan 실패', 'failed', 63)],
    },
    { state: 'awaiting_approval', step: 'risk_check', steps: AI_VALIDATED },
  ]),
  // W-06: 세 환경 모두 검증 통과, 승인 대기
  dep_approve: deployment('dep_approve', 'awaiting_approval', [
    { state: 'awaiting_approval', step: 'risk_check', steps: VALIDATED },
    { state: 'awaiting_approval', step: 'risk_check', attempt: 2, steps: AI_VALIDATED },
    { state: 'awaiting_approval', step: 'risk_check', steps: AI_VALIDATED },
  ]),
  // W-07: 온프레미스 apply 중, AWS 성공, GCP 실패
  dep_apply: deployment('dep_apply', 'running', [
    { state: 'applying', step: 'apply', steps: [st('이미지 pull', 'done', 42), st('terraform apply', 'done', 42), st('state 저장', 'running', 18), st('헬스체크', 'waiting')] },
    { state: 'succeeded', step: 'health_check', attempt: 2, url: URLS[1], steps: APPLIED },
    {
      state: 'failed',
      step: 'apply',
      error_summary: 'health check timeout on /healthz after 60s',
      steps: [st('이미지 pull', 'done', 42), st('terraform apply', 'failed', 63), st('state 저장', 'waiting'), st('헬스체크', 'waiting')],
    },
  ]),
  // W-08: 일부 성공 (GCP 헬스체크 실패)
  dep_result: deployment(
    'dep_result',
    'partially_succeeded',
    [
      { state: 'succeeded', step: 'health_check', url: URLS[0], image_digest: DIGEST, steps: APPLIED, health_summary: HEALTHY },
      { state: 'succeeded', step: 'health_check', attempt: 2, url: URLS[1], image_digest: DIGEST, steps: APPLIED, health_summary: HEALTHY },
      { state: 'failed', step: 'health_check', url: URLS[2], image_digest: DIGEST, error_summary: '헬스체크 실패 · 503', health_summary: '503 실패' },
    ],
    { finished_at: ago(1) },
  ),
}

// W-01 · W-09 이력 — 최신이 위
export const history: Deployment[] = [
  deployment('dep_approve', 'awaiting_approval', [
    { state: 'awaiting_approval', step: 'risk_check' },
    { state: 'awaiting_approval', step: 'risk_check' },
    { state: 'awaiting_approval', step: 'risk_check' },
  ], { version: 'v8', commit: 'f4e5d6c', commit_message: 'fix: 헬스체크 경로 수정 (#41)', created_at: ago(0) }),
  deployment('dep_41', 'succeeded', [
    { state: 'succeeded', step: 'health_check' },
    { state: 'succeeded', step: 'health_check' },
    { state: 'succeeded', step: 'health_check' },
  ], { version: 'v7', created_at: ago(12), finished_at: ago(12) }),
  deployment('dep_40', 'succeeded', [
    { state: 'succeeded', step: 'health_check' },
    { state: 'succeeded', step: 'health_check' },
    { state: 'succeeded', step: 'health_check' },
  ], { version: 'v6', commit: '9e21f0a', commit_message: 'chore: 의존성 업데이트 (#40)', created_at: ago(60 * 20), finished_at: ago(60 * 20) }),
  deployment('dep_39', 'failed', [
    { state: 'succeeded', step: 'health_check' },
    { state: 'failed', step: 'plan', attempt: 3 },
    { state: 'cancelled', step: 'plan' },
  ], { version: 'v5', commit: '3c4d5e6', commit_message: 'feat: 로그 레벨 설정 (#39)', created_at: ago(60 * 24 * 2), finished_at: ago(60 * 24 * 2) }),
]

export const plan: Plan = {
  deployment_id: 'dep_approve',
  targets: [
    { target_id: 'tgt_onprem', counts: { create: 0, update: 1, delete: 0 }, has_delete: false, risks: [], summary: '이미지 태그만 교체' },
    { target_id: 'tgt_aws', counts: { create: 6, update: 0, delete: 0 }, has_delete: false, risks: [] },
    { target_id: 'tgt_gcp', counts: { create: 5, update: 1, delete: 0 }, has_delete: false, risks: [] },
  ],
  ai_usage: aiUsage.summary,
}

export const planDetail: PlanDetail[] = [
  { target_id: 'tgt_onprem', resources: [{ address: 'docker_container.web', action: 'update' }], plan_text: '~ docker_container.web (image: …:9e21f0a → …:a1b2c3d)' },
  {
    target_id: 'tgt_aws',
    resources: [
      { address: 'aws_ecs_service.web', action: 'create', monthly_cost_krw: 18000 },
      { address: 'aws_lb.web', action: 'create', monthly_cost_krw: 21000 },
      { address: 'aws_security_group_rule.db', action: 'create', monthly_cost_krw: 0 },
      { address: 'aws_ecs_task_definition.web', action: 'create' },
      { address: 'aws_lb_target_group.web', action: 'create' },
      { address: 'aws_lb_listener.https', action: 'create' },
    ],
    plan_text: 'Plan: 6 to add, 0 to change, 0 to destroy.',
  },
  {
    target_id: 'tgt_gcp',
    resources: [
      { address: 'google_cloud_run_v2_service.web', action: 'create' },
      { address: 'google_cloud_run_v2_service_iam_member.public', action: 'create' },
      { address: 'google_artifact_registry_repository.app', action: 'update' },
      { address: 'google_service_account.run', action: 'create' },
      { address: 'google_project_iam_member.run', action: 'create' },
      { address: 'google_compute_region_network_endpoint_group.web', action: 'create' },
    ],
    plan_text: 'Plan: 5 to add, 1 to change, 0 to destroy.',
  },
]

export const logs: LogLine[] = [
  { seq: 1, at: '10:12:01', target_id: 'tgt_onprem', level: 'INFO', message: `docker pull ${IMAGE}` },
  { seq: 2, at: '10:12:03', target_id: 'tgt_aws', level: 'INFO', message: 'ecs: service sample-monolith updated (2/2 running)' },
  { seq: 3, at: '10:12:04', target_id: 'tgt_gcp', level: 'WARN', message: 'cloud run: revision not ready, retrying (1/3)' },
  { seq: 4, at: '10:12:09', target_id: 'tgt_gcp', level: 'ERROR', message: 'health check timeout on /healthz after 60s' },
  { seq: 5, at: '10:12:10', target_id: 'tgt_onprem', level: 'INFO', message: 'container started · listening on :3000' },
]

const AWS_MAIN_TF = `resource "aws_ecs_service" "web" {
  name            = "sample-monolith"
  launch_type     = "FARGATE"
  desired_count   = 2
  task_definition = aws_ecs_task_definition.web.arn
}

resource "aws_security_group_rule" "app" {
  source_security_group_id = aws_security_group.alb.id
}`

const ONPREM_MAIN_TF = `resource "docker_container" "web" {
  name  = "sample-monolith"
  image = "ghcr.io/team-daisy/sample-monolith:\${var.image_tag}"
  ports {
    internal = 8080
  }
}`

const GCP_MAIN_TF = `resource "google_cloud_run_v2_service" "web" {
  name     = "sample-monolith"
  location = "asia-northeast3"
  template {
    containers {
      image = "ghcr.io/team-daisy/sample-monolith:\${var.image_tag}"
    }
  }
}`

export const resources: Record<string, { address: string; type: string }[]> = {
  tgt_onprem: [{ address: 'docker_container.web', type: 'docker_container' }, { address: 'docker_network.app', type: 'docker_network' }],
  tgt_aws: [
    { address: 'aws_ecs_service.web', type: 'aws_ecs_service' },
    { address: 'aws_lb.web', type: 'aws_lb' },
    { address: 'aws_security_group_rule.db', type: 'aws_security_group_rule' },
  ],
  tgt_gcp: [{ address: 'google_cloud_run_v2_service.web', type: 'google_cloud_run_v2_service' }],
}

export const scripts: Script[] = [
  { script_id: 'scr_onprem_s3', target_id: 'tgt_onprem', type: 'onprem', version: 's3', origin: 'ai_generated', attempt: 1, validation: { validate: true, plan: true, risks: 0 }, status: 'verified', reuse_count: 4, last_used_at: ago(12), base_commit: COMMIT, input: 'deploy.yaml (port 8080)', ai_tokens: 2210, storage: null, created_at: ago(60 * 24 * 2), files: [{ path: 'onprem/main.tf', content: ONPREM_MAIN_TF }] },
  { script_id: 'scr_aws_s2', target_id: 'tgt_aws', type: 'aws', version: 's2', origin: 'ai_generated', attempt: 2, note: '보안 그룹 수정', validation: { validate: true, plan: true, risks: 0 }, status: 'verified', reuse_count: 1, last_used_at: ago(12), files: [{ path: 'aws/main.tf', content: AWS_MAIN_TF }], base_commit: COMMIT, input: 'deploy.yaml (port 8080)', ai_tokens: 3120, storage: null, created_at: ago(12) },
  { script_id: 'scr_gcp_s2', target_id: 'tgt_gcp', type: 'gcp', version: 's2', origin: 'ai_generated', attempt: 1, validation: { validate: true, plan: true, risks: 0 }, status: 'verified', reuse_count: 1, last_used_at: ago(12), base_commit: COMMIT, input: 'deploy.yaml (port 8080)', ai_tokens: 2940, storage: null, created_at: ago(13), files: [{ path: 'gcp/main.tf', content: GCP_MAIN_TF }] },
  { script_id: 'scr_aws_s1', target_id: 'tgt_aws', type: 'aws', version: 's1', origin: 'ai_generated', attempt: 3, validation: { validate: true, plan: false, risks: 0 }, status: 'discarded', reuse_count: 0, last_used_at: ago(60 * 24 * 2) },
]

export const generatedScript = `resource "aws_security_group_rule" "db" {
  type        = "ingress"
  from_port   = 5432
  to_port     = 5432
- cidr_blocks = ["0.0.0.0/0"]
+ source_security_group_id = aws_security_group.app.id
}`
