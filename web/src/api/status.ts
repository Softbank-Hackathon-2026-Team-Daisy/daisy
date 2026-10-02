import type { StatusTone } from '../components/StatusBadge.tsx'
import { t } from '../i18n/index.ts'
import type { DeploymentState, Step, TargetState } from './types.ts'

// 서버 상태 값 → Status Badge 톤 · 문구 (SPEC.md §2-5). 색은 와이어프레임 기준이에요
// 모르는 값이 오면 회색(대기 중 톤)으로 보여주고 깨지지 않아요
// 문구는 한국어 원문으로 두고, 꺼낼 때 t()로 바꿔요 (#75)
export type StatusView = { tone: StatusTone; label: string }

const DEPLOYMENT: Record<DeploymentState, StatusView> = {
  queued: { tone: 'queued', label: '대기 중' },
  running: { tone: 'running', label: '진행 중' },
  awaiting_approval: { tone: 'queued', label: '승인 대기' },
  succeeded: { tone: 'success', label: '성공' },
  partially_succeeded: { tone: 'warning', label: '일부 성공' },
  failed: { tone: 'failed', label: '실패' },
  cancelled: { tone: 'queued', label: '취소됨' },
}

const TARGET: Record<TargetState, StatusView> = {
  waiting: { tone: 'queued', label: '대기 중' },
  generating: { tone: 'running', label: '생성 중' },
  validating: { tone: 'running', label: '검증 중' },
  awaiting_approval: { tone: 'queued', label: '승인 대기' },
  applying: { tone: 'running', label: '배포 중' },
  verifying: { tone: 'running', label: '확인 중' },
  succeeded: { tone: 'success', label: '성공' },
  failed: { tone: 'failed', label: '실패' },
  cancelled: { tone: 'queued', label: '취소됨' },
}

const STEP: Record<Step, string> = {
  generate: '생성',
  validate: 'validate',
  plan: 'plan',
  risk_check: '위험 설정 검사',
  apply: 'apply',
  health_check: '헬스체크',
}

export const stepLabel = (step: Step) => t(STEP[step] ?? step)

// 서버 단계 목록(steps[].name, #13 가칭)의 코드 → 단계 줄 문구. terraform 명령은 그대로, 나머지는 번역해요
// 모르는 코드는 받은 그대로 보여줘요
const STEP_CODE: Record<string, () => string> = {
  generate: () => t('Terraform 생성 (AI)'),
  validate: () => 'terraform validate',
  plan: () => 'terraform plan',
  risk_check: () => t('위험 설정 검사'),
  apply: () => 'terraform apply',
  health_check: () => t('헬스체크'),
  image_pull: () => t('이미지 pull'),
  state_save: () => t('state 저장'),
}

export const serverStepLabel = (code: string) => (Object.hasOwn(STEP_CODE, code) ? STEP_CODE[code]() : code)

const UNKNOWN: StatusView = { tone: 'queued', label: '알 수 없음' }

const translated = (v: StatusView): StatusView => ({ tone: v.tone, label: t(v.label) })

export function deploymentStatus(state: string, kind?: 'deploy' | 'rollback' | null): StatusView {
  if (kind === 'rollback' && state === 'succeeded') return { tone: 'rolledback', label: t('롤백됨') }
  return translated(DEPLOYMENT[state as DeploymentState] ?? UNKNOWN)
}

export function targetStatus(state: string): StatusView {
  return translated(TARGET[state as TargetState] ?? UNKNOWN)
}

// "시도 n/3" — 첫 생성을 포함한 총 시도 횟수예요. "재시도"로 쓰지 않아요
// 생성 전이면 서버가 null을 줘요 (#46) → "시도 —"
export function attemptLabel(attempt: number | null | undefined) {
  return attempt == null ? t('시도 —') : t('시도 {n}/3', { n: attempt })
}
