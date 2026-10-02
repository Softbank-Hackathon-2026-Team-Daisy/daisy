import { attemptLabel, serverStepLabel, stepLabel, targetStatus, type StatusView } from '../api/status.ts'
import type { DeploymentTarget, Step } from '../api/types.ts'
import { ENV_LABEL } from '../components/env.ts'
import { t } from '../i18n/index.ts'
import type { StepItemState } from '../components/StepItem.tsx'
import { duration } from '../utils/format.ts'

// 배포 흐름 화면(W-05 ~ W-08)이 같이 쓰는 표시 규칙. 서버가 단계 목록(steps, #13 가칭)을 주면 그대로 쓰고,
// 없으면 현재 단계(step) · 상태(state)로 추정해요. step도 null이면(Jenkins 결과 수신 전, #46) 상태만으로 추정해요

export type StepView = { label: string; state: StepItemState; duration?: string }

const STEP_STATE: Record<string, StepItemState> = { waiting: 'pending', running: 'running', done: 'done', failed: 'failed', skipped: 'skipped' }

const GENERATE_STEPS: Step[] = ['generate', 'validate', 'plan', 'risk_check']
const APPLY_ORDER = ['applying', 'verifying', 'succeeded', 'failed']
const APPLY_STEPS = ['이미지 pull', 'terraform apply', 'state 저장', '헬스체크']

function fromServer(tg: DeploymentTarget): StepView[] | null {
  if (!tg.steps?.length) return null
  return tg.steps.map((s) => ({ label: s.name === 'generate' && tg.reused_script ? t('스크립트 재사용') : serverStepLabel(s.name), state: STEP_STATE[s.state] ?? 'pending', duration: duration(s.duration_ms, s.state === 'running') }))
}

// W-05 검증 단계
export function generateSteps(tg: DeploymentTarget): StepView[] {
  const server = fromServer(tg)
  if (server) return server
  const done = tg.state === 'awaiting_approval' || APPLY_ORDER.includes(tg.state)
  const current = tg.step
    ? GENERATE_STEPS.indexOf(tg.step)
    : tg.state === 'generating'
      ? 0
      : tg.state === 'validating'
        ? 1
        : -1 // 대기 · 단계를 모르는 실패는 어느 단계도 강조하지 않아요
  return GENERATE_STEPS.map((step, i) => ({
    label: step === 'generate' ? (tg.reused_script ? t('스크립트 재사용') : t('Terraform 생성 (AI)')) : step === 'risk_check' ? stepLabel('risk_check') : t('terraform {step}', { step: stepLabel(step) }),
    state: done || i < current ? 'done' : i === current ? (tg.state === 'failed' ? 'failed' : tg.state === 'waiting' ? 'pending' : 'running') : 'pending',
  }))
}

// W-07 apply 단계
export function applySteps(tg: DeploymentTarget): StepView[] {
  const server = fromServer(tg)
  if (server) return server
  const current = tg.state === 'verifying' ? 3 : tg.state === 'applying' ? 1 : tg.state === 'succeeded' ? 4 : tg.state === 'failed' ? (tg.step === 'health_check' ? 3 : 1) : 0
  return APPLY_STEPS.map((label, i) => ({
    label: t(label),
    state: i < current ? 'done' : i === current ? (tg.state === 'failed' ? 'failed' : tg.state === 'succeeded' ? 'done' : 'running') : 'pending',
  }))
}

// W-05 · W-05b 환경별 한 줄 설명과 상태
export function generateRow(tg: DeploymentTarget): { note: string; status: StatusView } {
  const how = tg.reused_script ? t('재사용 · 이미지 태그만 교체') : t('AI 생성')
  // 시도 횟수를 모르면(생성 전, #46) 시도 부분을 빼고 문장을 만들어요
  const attempt = tg.attempt == null ? null : attemptLabel(tg.attempt)
  if (tg.state === 'failed') return { note: tg.attempt ? t('{n}회 실패 · 중단', { n: tg.attempt }) : t('실패 · 중단'), status: { tone: 'failed', label: t('실패') } }
  if (tg.state === 'awaiting_approval' && tg.approval_state === 'approved')
    return { note: t('승인 완료 · 실행 대기'), status: { tone: 'success', label: t('승인됨') } }
  if (tg.state === 'awaiting_approval' || APPLY_ORDER.includes(tg.state))
    return { note: attempt ? t('{how} · {attempt} 통과', { how, attempt }) : t('{how} · 통과', { how }), status: { tone: 'success', label: t('검증 통과') } }
  if (tg.state === 'waiting') return { note: t('대기 중'), status: targetStatus('waiting') }
  if (tg.state === 'cancelled') return { note: tg.cancel_requested_at ? t('취소 요청으로 멈췄어요') : t('취소됨'), status: targetStatus('cancelled') }
  if (tg.state === 'generating') return { note: attempt ? `${how} · ${attempt}` : how, status: targetStatus('generating') }
  if (tg.error_summary)
    return {
      note: attempt ? t('{how} · 위험 설정 발견 → AI 수정 중 · {attempt}', { how, attempt }) : t('{how} · 위험 설정 발견 → AI 수정 중', { how }),
      status: { tone: 'running', label: t('검증 중') },
    }
  const step = tg.step ? stepLabel(tg.step) : t('검증')
  return {
    note: attempt ? t('{how} · {step} 실행 중 · {attempt}', { how, step, attempt }) : t('{how} · {step} 실행 중', { how, step }),
    status: { tone: 'running', label: t('검증 중') },
  }
}

export const envName = (tg: DeploymentTarget) => t(ENV_LABEL[tg.type])

// 그 환경이 apply 단계까지 갔는지 — 생성 · 검증에서 실패한 환경은 아니에요 (앱 RunLogic.reachedApply와 같은 규칙)
export function reachedApply(tg: DeploymentTarget) {
  if (tg.state === 'failed') return tg.step === 'apply' || tg.step === 'health_check'
  return tg.state === 'applying' || tg.state === 'verifying' || tg.state === 'succeeded'
}

// 실패한 단계 이름 — "헬스체크" · "apply" · "생성 · 검증" (번역된 문구). 단계를 모르면 null
// 문장은 부르는 쪽에서 통째로 번역해요 ("{step}에서 실패" — 언어마다 어순이 달라서)
export const failedStep = (tg: DeploymentTarget) =>
  tg.step === 'health_check' ? t('헬스체크') : tg.step === 'apply' ? 'apply' : tg.step ? t('생성 · 검증') : null

// 버전 표시 — 서버가 version을 아직 안 줘서(후순위, #46) 짧은 커밋으로 대신해요
export const versionLabel = (d: { version?: string; commit: string }) => d.version ?? d.commit.slice(0, 7)

export const names = (list: DeploymentTarget[]) => list.map(envName).join(' · ')
