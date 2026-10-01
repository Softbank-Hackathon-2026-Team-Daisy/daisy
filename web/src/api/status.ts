import type { StatusTone } from '../components/StatusBadge.tsx'
import type { DeploymentState, Step, TargetState } from './types.ts'

// 서버 상태 값 → Status Badge 톤 · 문구 (SPEC.md §2-5). 색은 와이어프레임 기준이에요
// 모르는 값이 오면 회색(대기 중 톤)으로 보여주고 깨지지 않아요
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

export const STEP_LABEL: Record<Step, string> = {
  generate: '생성',
  validate: 'validate',
  plan: 'plan',
  risk_check: '위험 설정 검사',
  apply: 'apply',
  health_check: '헬스체크',
}

const UNKNOWN: StatusView = { tone: 'queued', label: '알 수 없음' }

export function deploymentStatus(state: string, kind?: 'deploy' | 'rollback'): StatusView {
  if (kind === 'rollback' && state === 'succeeded') return { tone: 'rolledback', label: '롤백됨' }
  return DEPLOYMENT[state as DeploymentState] ?? UNKNOWN
}

export function targetStatus(state: string): StatusView {
  return TARGET[state as TargetState] ?? UNKNOWN
}

// "시도 n/3" — 첫 생성을 포함한 총 시도 횟수예요. "재시도"로 쓰지 않아요
export function attemptLabel(attempt: number) {
  return `시도 ${attempt}/3`
}
