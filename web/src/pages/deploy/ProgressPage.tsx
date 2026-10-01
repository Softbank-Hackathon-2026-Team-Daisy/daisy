import { useEffect, useRef } from 'react'
import { useNavigate, useParams } from 'react-router'
import { api } from '../../api/endpoints.ts'
import { deploymentStatus, targetStatus } from '../../api/status.ts'
import type { Deployment } from '../../api/types.ts'
import { POLL_MS, useResource } from '../../api/useResource.ts'
import Button from '../../components/Button.tsx'
import DeployLane from '../../components/DeployLane.tsx'
import LogViewer from '../../components/LogViewer.tsx'
import PageHeader from '../../components/PageHeader.tsx'
import StatusBadge from '../../components/StatusBadge.tsx'
import Stepper from '../../components/Stepper.tsx'
import { paths } from '../../paths.ts'
import { applySteps } from '../flow.ts'
import TransitionGate from '../loading/TransitionGate.tsx'
import { ErrorBlock, LoadingBlock } from '../Loading.tsx'
import '../page.css'

// W-07 배포 중 (STEP 5) — 환경별 terraform apply를 레인 3개로. 로그는 서버 SSE 전까지 5초 폴링(A-07), 배포가 끝나면 멈춰요
const APPLY_STARTED = new Set(['applying', 'verifying', 'succeeded', 'failed'])
const FINISHED = new Set(['succeeded', 'partially_succeeded', 'failed', 'cancelled'])

function ProgressPage() {
  const { deploymentId = '' } = useParams()
  const deployment = useResource(() => api.getDeployment(deploymentId), [deploymentId], POLL_MS, (d) => FINISHED.has(d.state))
  const d = deployment.data
  // L-03: 승인에서 넘어왔으면 한 환경이라도 apply를 시작할 때까지 전환 로딩
  const ready = !!d && d.targets.some((t) => APPLY_STARTED.has(t.state))

  return (
    <TransitionGate kind="l03" ready={ready} meta={d ? `Step 5 · ${d.targets.length} envs` : 'Step 5'}>
      {deployment.error ? <ErrorBlock error={deployment.error} /> : !d ? <LoadingBlock /> : <ProgressView key={d.id} d={d} />}
    </TransitionGate>
  )
}

function ProgressView({ d }: { d: Deployment }) {
  const navigate = useNavigate()
  const { projectId = '' } = useParams()
  const finished = FINISHED.has(d.state)
  // 끝난 배포는 로그를 한 번만 불러요
  const logs = useResource(() => api.getLogs(d.id), [d.id, finished], finished ? undefined : POLL_MS)
  const status = deploymentStatus(d.state, d.kind)

  // 끝나면 W-08로 넘어가요 (처음부터 끝난 배포였으면 버튼으로)
  const wasRunning = useRef(!finished)
  useEffect(() => {
    if (wasRunning.current && finished) navigate(paths.result(projectId, d.id))
    wasRunning.current = !finished
  }, [finished, navigate, projectId, d.id])

  const typeOf = (targetId: string) => d.targets.find((t) => t.target_id === targetId)?.type ?? 'onprem'

  return (
    <div className="page">
      <Stepper current={5} />
      <PageHeader
        overline="Step 5"
        title="배포 중"
        badge={<StatusBadge tone={status.tone}>{status.label}</StatusBadge>}
        description={`${d.targets.length}개 환경에 terraform apply를 동시에 실행하고 있어요. 환경마다 state는 따로 저장해요.`}
      />

      <div className="page__row page__row--3">
        {d.targets.map((t) => {
          const s = targetStatus(t.state)
          return <DeployLane key={t.target_id} env={t.type} region={t.title ?? t.target_id} tone={s.tone} label={s.label} steps={applySteps(t)} />
        })}
      </div>

      <LogViewer
        lines={(logs.data ?? []).map((l) => ({ key: l.seq, time: l.at, env: typeOf(l.target_id), level: l.level, message: l.message }))}
      />

      {finished && (
        <div className="page__actions">
          <Button variant="secondary" onClick={() => navigate(paths.result(projectId, d.id))}>
            결과 보기
          </Button>
        </div>
      )}
    </div>
  )
}

export default ProgressPage
