import { useEffect, useRef, useState } from 'react'
import { useNavigate, useParams } from 'react-router'
import { useAuth } from '../../api/auth.ts'
import { api } from '../../api/endpoints.ts'
import type { Deployment } from '../../api/types.ts'
import { useAction } from '../../api/useAction.ts'
import { POLL_MS, useResource } from '../../api/useResource.ts'
import Alert from '../../components/Alert.tsx'
import Button from '../../components/Button.tsx'
import CodeBlock from '../../components/CodeBlock.tsx'
import EnvStatusRow from '../../components/EnvStatusRow.tsx'
import PageHeader from '../../components/PageHeader.tsx'
import Panel from '../../components/Panel.tsx'
import StepItem from '../../components/StepItem.tsx'
import Stepper from '../../components/Stepper.tsx'
import Tabs from '../../components/Tabs.tsx'
import Toast from '../../components/Toast.tsx'
import { paths } from '../../paths.ts'
import { envName, generateRow, generateSteps, names } from '../flow.ts'
import TransitionGate from '../loading/TransitionGate.tsx'
import { ErrorBlock, LoadingBlock } from '../Loading.tsx'
import ReadOnlyNote from '../ReadOnlyNote.tsx'
import '../page.css'

// W-05 인프라 코드 생성 · 검증 (STEP 4) · W-05b 한 환경만 멈췄을 때. 서버 SSE 전까지 5초 폴링, 생성 단계가 끝나면 멈춰요
const BUSY = new Set(['waiting', 'generating', 'validating'])
const stillGenerating = (d: Deployment) => d.state === 'queued' || (d.targets ?? []).some((t) => BUSY.has(t.state))

function GeneratePage() {
  const { deploymentId = '' } = useParams()
  const deployment = useResource(() => api.getDeployment(deploymentId), [deploymentId], POLL_MS, (d) => !stillGenerating(d))
  const d = deployment.data
  // L-02: 환경 선택에서 넘어왔으면 생성이 시작될 때까지(작업 큐 대기가 끝날 때까지) 전환 로딩
  const ready = !!d && d.state !== 'queued'

  return (
    <TransitionGate kind="l02" ready={ready} meta={d ? `Step 4 · ${d.targets.length} envs` : 'Step 4'}>
      {deployment.error ? <ErrorBlock error={deployment.error} /> : !d ? <LoadingBlock /> : <GenerateView key={d.id} d={d} />}
    </TransitionGate>
  )
}

function GenerateView({ d }: { d: Deployment }) {
  const navigate = useNavigate()
  const { projectId = '' } = useParams()
  const failed = d.targets.filter((t) => t.state === 'failed')
  const busy = d.targets.some((t) => BUSY.has(t.state))
  const approvable = !busy && d.targets.some((t) => t.state === 'awaiting_approval')
  const [tab, setTab] = useState(() => (failed[0] ?? d.targets.find((t) => BUSY.has(t.state)) ?? d.targets[0]).target_id)
  const target = d.targets.find((t) => t.target_id === tab) ?? d.targets[0]
  const script = useResource(() => api.getScript(d.id, target.target_id), [d.id, target.target_id])
  const { run, pending, error: retryError } = useAction()
  const viewer = useAuth().role === 'viewer'
  const [toastOpen, setToastOpen] = useState(true)

  // 검증이 끝나 승인 대기로 바뀌면 W-06으로 넘어가요 (처음부터 승인 대기였으면 버튼으로)
  const wasBusy = useRef(busy)
  useEffect(() => {
    if (wasBusy.current && approvable) navigate(paths.approve(projectId, d.id))
    wasBusy.current = busy
  }, [busy, approvable, navigate, projectId, d.id])

  // 실패한 환경만 고른 새 배포 (#13 서버 결정, 시도 1/3부터)
  const retry = async () => {
    const next = await run((key) => api.createDeployment(projectId, d.commit, failed.map((t) => t.target_id), key), '다시 시도하지 못했어요')
    if (next) navigate(paths.generate(projectId, next.id), { state: { transition: 'l02' } })
  }

  const tabs = (
    <Tabs
      label="환경"
      value={target.target_id}
      onChange={setTab}
      items={d.targets.map((t) => ({ id: t.target_id, label: envName(t), env: t.type }))}
    />
  )

  // W-05b — 한 환경이 3번 모두 실패해서 멈췄어요. 나머지는 계속 진행해요 (Q7)
  if (failed.length > 0) {
    const f = failed[0]
    const who = names(failed)
    return (
      <div className="page">
        <Stepper current={4} />
        <PageHeader
          overline="Step 4"
          title={`${who}만 멈췄어요`}
          description={`${who}는 3번 모두 실패해서 멈췄어요. ${names(d.targets.filter((t) => t.state !== 'failed'))}는 그대로 계속 진행해요.`}
        />
        <Alert type="danger" title={`${envName(f)} · ${f.attempt}회 시도 모두 실패`}>
          {f.error_summary}
        </Alert>
        <div className="page__row page__row--2">
          <Panel title={`${envName(f)} 시도 기록`}>
            <div>
              {generateSteps(f).map((s) => (
                <StepItem key={s.label} {...s} />
              ))}
            </div>
          </Panel>
          <Panel title="환경별 상태">
            {d.targets.map((t) => {
              const row = generateRow(t)
              return <EnvStatusRow key={t.target_id} env={t.type} note={row.note} tone={row.status.tone} label={row.status.label} />
            })}
          </Panel>
        </div>
        {toastOpen && (
          <Toast type="error" title={`${who} 검증 실패 · 나머지 환경은 계속`} onClose={() => setToastOpen(false)}>
            오류 로그와 AI 수정 이력을 확인해 주세요
          </Toast>
        )}
        {retryError && <Alert type="danger" title="다시 시도하지 못했어요">{retryError}</Alert>}
        {viewer && <ReadOnlyNote action="다시 시도할" />}
        <div className="page__actions">
          <Button variant="outline" onClick={() => navigate(paths.scripts(projectId))}>
            오류 로그 보기
          </Button>
          <Button variant="secondary" disabled={viewer || pending} onClick={() => void retry()}>
            {pending ? '시작하는 중…' : `${who}만 다시 시도`}
          </Button>
          {approvable && (
            <Button variant="secondary" onClick={() => navigate(paths.approve(projectId, d.id))}>
              나머지 환경 plan 확인하기
            </Button>
          )}
        </div>
      </div>
    )
  }

  const row = generateRow(target)

  return (
    <div className="page">
      <Stepper current={4} />
      <PageHeader
        overline="Step 4"
        title="인프라 코드 생성 · 검증"
        description="AI가 환경별 Terraform을 만들고 validate · plan · 위험 설정 검사를 통과할 때까지 최대 3번 고쳐요."
      />

      <Panel title="환경별 진행">
        {d.targets.map((t) => {
          const r = generateRow(t)
          return <EnvStatusRow key={t.target_id} env={t.type} note={r.note} tone={r.status.tone} label={r.status.label} />
        })}
      </Panel>

      {tabs}

      <div className="page__row page__row--2">
        <Panel title={`${envName(target)} 검증 단계`}>
          <div>
            {generateSteps(target).map((s) => (
              <StepItem key={s.label} {...s} />
            ))}
          </div>
          {target.error_summary && (
            <Alert type="danger" title={row.status.label === '검증 중' ? '위험 설정 발견 · AI가 수정 중' : '검증 실패'}>
              {target.error_summary}
            </Alert>
          )}
        </Panel>
        <Panel title="생성된 스크립트">
          {script.error ? (
            <ErrorBlock error={script.error} />
          ) : !script.data ? (
            <LoadingBlock />
          ) : (script.data.files ?? []).length === 0 ? (
            <p className="t-body-sm t-muted">아직 스크립트가 없어요</p>
          ) : (
            (script.data.files ?? []).map((f) => (
              <CodeBlock
                key={f.path}
                ai={!target.reused_script}
                file={`${f.path} · ${target.reused_script ? '검증된 스크립트 재사용' : target.attempt > 1 ? `AI 수정 ${target.attempt}회차` : 'AI 생성'}`}
                code={f.content}
              />
            ))
          )}
        </Panel>
      </div>

      {approvable && (
        <div className="page__actions">
          <Button variant="secondary" onClick={() => navigate(paths.approve(projectId, d.id))}>
            변경 사항 확인하기
          </Button>
        </div>
      )}
    </div>
  )
}

export default GeneratePage
