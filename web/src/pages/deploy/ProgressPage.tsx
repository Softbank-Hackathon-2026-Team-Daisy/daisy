import { useEffect, useRef, useState } from 'react'
import { useNavigate, useParams } from 'react-router'
import { api, isMocked } from '../../api/endpoints.ts'
import { pollFor } from '../../api/projectLive.ts'
import { deploymentStatus, targetStatus } from '../../api/status.ts'
import type { Deployment } from '../../api/types.ts'
import { liveLogs, useDeploymentLive, type LiveLogLine } from '../../api/useRealtime.ts'
import { POLL_MS, useResource } from '../../api/useResource.ts'
import Button from '../../components/Button.tsx'
import DeployLane from '../../components/DeployLane.tsx'
import LogViewer from '../../components/LogViewer.tsx'
import PageHeader from '../../components/PageHeader.tsx'
import StatusBadge from '../../components/StatusBadge.tsx'
import Stepper from '../../components/Stepper.tsx'
import { t } from '../../i18n/index.ts'
import { paths } from '../../paths.ts'
import { applySteps } from '../flow.ts'
import TransitionGate from '../loading/TransitionGate.tsx'
import { ErrorBlock, LoadingBlock } from '../Loading.tsx'
import '../page.css'

// W-07 배포 중 (STEP 5) — 환경별 terraform apply를 레인 3개로. 로그는 배포 채널(SSE) log.batch로 받고,
// 채널이 없으면(목업) A-07을 5초 폴링해요. 배포가 끝나면 멈춰요
const APPLY_STARTED = new Set(['applying', 'verifying', 'succeeded', 'failed'])
const FINISHED = new Set(['succeeded', 'partially_succeeded', 'failed', 'cancelled'])

function ProgressPage() {
  const { deploymentId = '' } = useParams()
  // SSE 로그는 seq로 모아요 — 다시 붙을 때(resync) 처음부터 재생돼도 겹치지 않게
  const [sseLines, setSseLines] = useState<Map<number, LiveLogLine>>(() => new Map())
  const live = useDeploymentLive(deploymentId, (lines) =>
    setSseLines((prev) => {
      const next = new Map(prev)
      for (const l of lines) next.set(l.seq, l)
      return next
    }),
  )
  const deployment = useResource(() => api.getDeployment(deploymentId), [deploymentId, live.tick], pollFor(live.state), (d) => FINISHED.has(d.state))
  const d = deployment.data
  // L-03: 승인에서 넘어왔으면 한 환경이라도 apply를 시작할 때까지 전환 로딩
  const ready = !!d && d.targets.some((tg) => APPLY_STARTED.has(tg.state))

  return (
    <TransitionGate kind="l03" ready={ready} meta={d ? `Step 5 · ${d.targets.length} envs` : 'Step 5'}>
      {deployment.error ? <ErrorBlock error={deployment.error} /> : !d ? <LoadingBlock /> : <ProgressView key={d.id} d={d} sseLines={[...sseLines.values()].sort((a, b) => a.seq - b.seq)} />}
    </TransitionGate>
  )
}

function ProgressView({ d, sseLines }: { d: Deployment; sseLines: LiveLogLine[] }) {
  const navigate = useNavigate()
  const { projectId = '' } = useParams()
  const finished = FINISHED.has(d.state)
  // SSE로 받을 때는 A-07을 처음 한 번만 불러 이전 로그를 채우고(#56), 새 줄은 SSE로 받아요. 같은 seq는 한 줄로 합쳐요
  // SSE가 없으면 A-07을 5초 폴링, 끝난 배포는 한 번만
  const sse = liveLogs()
  const logs = useResource(() => api.getLogs(d.id), [d.id, finished, sse], sse || finished ? undefined : POLL_MS)
  const lines = sse ? mergeLogs(logs.data ?? [], sseLines) : (logs.data ?? [])
  const status = deploymentStatus(d.state, d.kind)

  // 끝나면 W-08로 넘어가요 (처음부터 끝난 배포였으면 버튼으로)
  const wasRunning = useRef(!finished)
  useEffect(() => {
    if (wasRunning.current && finished) navigate(paths.result(projectId, d.id))
    wasRunning.current = !finished
  }, [finished, navigate, projectId, d.id])

  // 콘솔 줄(target_id null)은 특정 환경이 아니라 실행 공통이에요
  const typeOf = (targetId: string | null) => (targetId ? (d.targets.find((tg) => tg.target_id === targetId)?.type ?? null) : null)

  return (
    <div className="page">
      <Stepper current={5} />
      <PageHeader
        overline="Step 5"
        mock={isMocked('getDeployment') || (!sse && isMocked('getLogs'))}
        title={t('배포 중')}
        badge={<StatusBadge tone={status.tone}>{status.label}</StatusBadge>}
        description={t('{n}개 환경에 terraform apply를 동시에 실행하고 있어요. 환경마다 state는 따로 저장해요.', { n: d.targets.length })}
      />

      <div className="page__row page__row--3">
        {d.targets.map((tg) => {
          const s = targetStatus(tg.state)
          return <DeployLane key={tg.target_id} env={tg.type} region={tg.title ?? tg.target_id} tone={s.tone} label={s.label} steps={applySteps(tg)} />
        })}
      </div>

      <LogViewer
        lines={lines.map((l) => ({ key: l.seq, time: l.at, env: typeOf(l.target_id), level: l.level, message: l.message }))}
      />

      {finished && (
        <div className="page__actions">
          <Button variant="secondary" onClick={() => navigate(paths.result(projectId, d.id))}>
            {t('결과 보기')}
          </Button>
        </div>
      )}
    </div>
  )
}

function mergeLogs(history: { seq: number }[], live: LiveLogLine[]) {
  const map = new Map<number, (typeof history)[number] | LiveLogLine>()
  for (const l of history) map.set(l.seq, l)
  for (const l of live) map.set(l.seq, l)
  return [...map.values()].sort((a, b) => a.seq - b.seq) as LiveLogLine[]
}

export default ProgressPage
