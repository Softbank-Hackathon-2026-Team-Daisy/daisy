import { attemptLabel, STEP_LABEL, targetStatus, type StatusView } from '../api/status.ts'
import type { DeploymentTarget, Step } from '../api/types.ts'
import { ENV_LABEL } from '../components/env.ts'
import type { StepItemState } from '../components/StepItem.tsx'
import { duration } from '../utils/format.ts'

// 배포 흐름 화면(W-05 ~ W-08)이 같이 쓰는 표시 규칙. 서버가 단계 목록(steps, #13 가칭)을 주면 그대로 쓰고,
// 없으면 현재 단계(step) · 상태(state)로 추정해요. step도 null이면(Jenkins 결과 수신 전, #46) 상태만으로 추정해요

export type StepView = { label: string; state: StepItemState; duration?: string }

const STEP_STATE: Record<string, StepItemState> = { waiting: 'pending', running: 'running', done: 'done', failed: 'failed', skipped: 'skipped' }

const GENERATE_STEPS: Step[] = ['generate', 'validate', 'plan', 'risk_check']
const APPLY_ORDER = ['applying', 'verifying', 'succeeded', 'failed']
const APPLY_STEPS = ['이미지 pull', 'terraform apply', 'state 저장', '헬스체크']

function fromServer(t: DeploymentTarget): StepView[] | null {
  if (!t.steps?.length) return null
  return t.steps.map((s) => ({ label: s.name, state: STEP_STATE[s.state] ?? 'pending', duration: duration(s.duration_ms, s.state === 'running') }))
}

// W-05 검증 단계
export function generateSteps(t: DeploymentTarget): StepView[] {
  const server = fromServer(t)
  if (server) return server
  const done = t.state === 'awaiting_approval' || APPLY_ORDER.includes(t.state)
  const current = t.step
    ? GENERATE_STEPS.indexOf(t.step)
    : t.state === 'generating'
      ? 0
      : t.state === 'validating'
        ? 1
        : -1 // 대기 · 단계를 모르는 실패는 어느 단계도 강조하지 않아요
  return GENERATE_STEPS.map((step, i) => ({
    label: step === 'generate' ? (t.reused_script ? '스크립트 재사용' : 'Terraform 생성 (AI)') : step === 'risk_check' ? STEP_LABEL.risk_check : `terraform ${STEP_LABEL[step]}`,
    state: done || i < current ? 'done' : i === current ? (t.state === 'failed' ? 'failed' : t.state === 'waiting' ? 'pending' : 'running') : 'pending',
  }))
}

// W-07 apply 단계
export function applySteps(t: DeploymentTarget): StepView[] {
  const server = fromServer(t)
  if (server) return server
  const current = t.state === 'verifying' ? 3 : t.state === 'applying' ? 1 : t.state === 'succeeded' ? 4 : t.state === 'failed' ? (t.step === 'health_check' ? 3 : 1) : 0
  return APPLY_STEPS.map((label, i) => ({
    label,
    state: i < current ? 'done' : i === current ? (t.state === 'failed' ? 'failed' : t.state === 'succeeded' ? 'done' : 'running') : 'pending',
  }))
}

// W-05 · W-05b 환경별 한 줄 설명과 상태
export function generateRow(t: DeploymentTarget): { note: string; status: StatusView } {
  const how = t.reused_script ? '재사용 · 이미지 태그만 교체' : 'AI 생성'
  const attempt = attemptLabel(t.attempt)
  if (t.state === 'failed') return { note: t.attempt ? `${t.attempt}회 실패 · 중단` : '실패 · 중단', status: { tone: 'failed', label: '실패' } }
  if (t.state === 'awaiting_approval' || APPLY_ORDER.includes(t.state))
    return { note: `${how} · ${attempt} 통과`, status: { tone: 'success', label: '검증 통과' } }
  if (t.state === 'waiting') return { note: '대기 중', status: targetStatus('waiting') }
  if (t.state === 'generating') return { note: `${how} · ${attempt}`, status: targetStatus('generating') }
  if (t.error_summary) return { note: `${how} · 위험 설정 발견 → AI 수정 중 · ${attempt}`, status: { tone: 'running', label: '검증 중' } }
  return { note: `${how} · ${t.step ? STEP_LABEL[t.step] : '검증'} 실행 중 · ${attempt}`, status: { tone: 'running', label: '검증 중' } }
}

export const envName = (t: DeploymentTarget) => ENV_LABEL[t.type]

// 그 환경이 apply 단계까지 갔는지 — 생성 · 검증에서 실패한 환경은 아니에요 (앱 RunLogic.reachedApply와 같은 규칙)
export function reachedApply(t: DeploymentTarget) {
  if (t.state === 'failed') return t.step === 'apply' || t.step === 'health_check'
  return t.state === 'applying' || t.state === 'verifying' || t.state === 'succeeded'
}

// 실패한 단계 문구 — "헬스체크에서" · "apply에서" · "생성 · 검증에서". 단계를 모르면 빈 문자열
export const failedAt = (t: DeploymentTarget) =>
  t.step === 'health_check' ? '헬스체크에서' : t.step === 'apply' ? 'apply에서' : t.step ? '생성 · 검증에서' : ''

// 버전 표시 — 서버가 version을 아직 안 줘서(후순위, #46) 짧은 커밋으로 대신해요
export const versionLabel = (d: { version?: string; commit: string }) => d.version ?? d.commit.slice(0, 7)

export const names = (list: DeploymentTarget[]) => list.map(envName).join(' · ')
