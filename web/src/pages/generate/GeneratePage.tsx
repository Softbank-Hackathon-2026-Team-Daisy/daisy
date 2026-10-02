import { useEffect, useRef, useState } from 'react'
import { useNavigate, useParams } from 'react-router'
import { useAuth } from '../../api/auth.ts'
import { USE_MOCK } from '../../api/client.ts'
import { api, isMocked } from '../../api/endpoints.ts'
import type { Deployment } from '../../api/types.ts'
import { useAction } from '../../api/useAction.ts'
import { pollFor } from '../../api/projectLive.ts'
import { useDeploymentLive } from '../../api/useRealtime.ts'
import { useResource } from '../../api/useResource.ts'
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
import { t } from '../../i18n/index.ts'
import { envName, generateRow, generateSteps, names } from '../flow.ts'
import TransitionGate from '../loading/TransitionGate.tsx'
import { ErrorBlock, LoadingBlock } from '../Loading.tsx'
import ReadOnlyNote from '../ReadOnlyNote.tsx'
import '../page.css'

// W-05 인프라 코드 생성 · 검증 (STEP 4) · W-05b 한 환경만 멈췄을 때. 서버 SSE 전까지 5초 폴링, 생성 단계가 끝나면 멈춰요
const BUSY = new Set(['waiting', 'generating', 'validating'])
const stillGenerating = (d: Deployment) => d.state === 'queued' || (d.targets ?? []).some((tg) => BUSY.has(tg.state))

function GeneratePage() {
  const { deploymentId = '' } = useParams()
  // 배포 채널 이벤트(step · target · plan.ready)가 오면 다시 불러요. SSE가 없으면 5초 폴링
  const live = useDeploymentLive(deploymentId)
  const deployment = useResource(() => api.getDeployment(deploymentId), [deploymentId, live.tick], pollFor(live.state), (d) => !stillGenerating(d))
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
  const failed = d.targets.filter((tg) => tg.state === 'failed')
  const busy = d.targets.some((tg) => BUSY.has(tg.state))
  const approvable = !busy && d.targets.some((tg) => tg.state === 'awaiting_approval')
  const [tab, setTab] = useState(() => (failed[0] ?? d.targets.find((tg) => BUSY.has(tg.state)) ?? d.targets[0]).target_id)
  const target = d.targets.find((tg) => tg.target_id === tab) ?? d.targets[0]
  // 실서버 모드인데 스크립트 API(WR-07)가 아직 없으면 목업 코드를 실제 배포처럼 보여주지 않아요
  const scriptReady = USE_MOCK || !isMocked('getScript')
  const script = useResource(() => (scriptReady ? api.getScript(d.id, target.target_id) : Promise.resolve(null)), [d.id, target.target_id, scriptReady])
  const { run, pending, error: retryError } = useAction()
  const viewer = useAuth().role === 'viewer'
  const [toastOpen, setToastOpen] = useState(true)

  // 검증이 끝나 승인 대기로 바뀌면 W-06으로 넘어가요 (처음부터 승인 대기였으면 버튼으로)
  const wasBusy = useRef(busy)
  useEffect(() => {
    if (wasBusy.current && approvable) navigate(paths.approve(projectId, d.id))
    wasBusy.current = busy
  }, [busy, approvable, navigate, projectId, d.id])

  // 실패한 환경만 새 배포로 다시 시도 — POST /deployments/{id}/retry (10/2 확정, 시도 1/3부터)
  const retry = async () => {
    const ids = failed.map((tg) => tg.target_id)
    const next = await run((key) => api.retry(d.id, ids, key), t('다시 시도하지 못했어요'), ['retry', d.id, ids])
    if (next) navigate(paths.generate(projectId, next.id), { state: { transition: 'l02' } })
  }

  const tabs = (
    <Tabs
      label={t('환경')}
      value={target.target_id}
      onChange={setTab}
      items={d.targets.map((tg) => ({ id: tg.target_id, label: envName(tg), env: tg.type }))}
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
          mock={isMocked('getDeployment')}
          title={t('{who}만 멈췄어요', { who })}
          description={t('{who}는 3번 모두 실패해서 멈췄어요. {others}는 그대로 계속 진행해요.', { who, others: names(d.targets.filter((tg) => tg.state !== 'failed')) })}
        />
        <Alert type="danger" title={`${envName(f)} · ${f.attempt ? t('{n}회 시도 모두 실패', { n: f.attempt }) : t('실패')}`}>
          {f.error_summary}
        </Alert>
        <div className="page__row page__row--2">
          <Panel title={t('{env} 시도 기록', { env: envName(f) })}>
            <div>
              {generateSteps(f).map((s) => (
                <StepItem key={s.label} {...s} />
              ))}
            </div>
          </Panel>
          <Panel title={t('환경별 상태')}>
            {d.targets.map((tg) => {
              const row = generateRow(tg)
              return <EnvStatusRow key={tg.target_id} env={tg.type} note={row.note} tone={row.status.tone} label={row.status.label} />
            })}
          </Panel>
        </div>
        {toastOpen && (
          <Toast type="error" title={t('{who} 검증 실패 · 나머지 환경은 계속', { who })} onClose={() => setToastOpen(false)}>
            {t('오류 로그와 AI 수정 이력을 확인해 주세요')}
          </Toast>
        )}
        {retryError && <Alert type="danger" title={t('다시 시도하지 못했어요')}>{retryError}</Alert>}
        {viewer && <ReadOnlyNote message={t('읽기 전용 계정이라 다시 시도할 수 없어요.')} />}
        <div className="page__actions">
          <Button variant="outline" onClick={() => navigate(paths.scripts(projectId))}>
            {t('오류 로그 보기')}
          </Button>
          <Button variant="secondary" disabled={viewer || pending} onClick={() => void retry()}>
            {pending ? t('시작하는 중…') : t('{who}만 다시 시도', { who })}
          </Button>
          {approvable && (
            <Button variant="secondary" onClick={() => navigate(paths.approve(projectId, d.id))}>
              {t('나머지 환경 plan 확인하기')}
            </Button>
          )}
        </div>
      </div>
    )
  }

  const row = generateRow(target)
  const cancelled = d.state === 'cancelled'

  return (
    <div className="page">
      <Stepper current={4} />
      <PageHeader
        overline="Step 4"
        mock={isMocked('getDeployment')}
        title={t('인프라 코드 생성 · 검증')}
        description={t('AI가 환경별 Terraform을 만들고 validate · plan · 위험 설정 검사를 통과할 때까지 최대 3번 고쳐요.')}
      />

      {cancelled && (
        <Alert type="info" title={t('배포가 취소됐어요')}>
          {t('이력에서 다시 배포하거나 롤백할 수 있어요.')}
        </Alert>
      )}

      <Panel title={t('환경별 진행')}>
        {d.targets.map((tg) => {
          const r = generateRow(tg)
          return <EnvStatusRow key={tg.target_id} env={tg.type} note={r.note} tone={r.status.tone} label={r.status.label} />
        })}
      </Panel>

      {tabs}

      <div className="page__row page__row--2">
        <Panel title={t('{env} 검증 단계', { env: envName(target) })}>
          <div>
            {generateSteps(target).map((s) => (
              <StepItem key={s.label} {...s} />
            ))}
          </div>
          {target.error_summary && (
            <Alert type="danger" title={row.status.label === t('검증 중') ? t('위험 설정 발견 · AI가 수정 중') : t('검증 실패')}>
              {target.error_summary}
            </Alert>
          )}
        </Panel>
        {/* 스크립트 API(WR-07)가 목업으로 답할 때만 이 칸에 MOCK — 실서버 모드에서는 목업 코드 대신 안내만 보여줘요 */}
        <Panel title={t('생성된 스크립트')} mock={scriptReady && isMocked('getScript')}>
          {!scriptReady ? (
            <p className="t-body-sm t-muted">{t('생성된 Terraform 코드는 곧 여기에서 볼 수 있어요')}</p>
          ) : script.error ? (
            <ErrorBlock error={script.error} />
          ) : !script.data ? (
            <LoadingBlock />
          ) : (script.data.files ?? []).length === 0 ? (
            <p className="t-body-sm t-muted">{t('아직 스크립트가 없어요')}</p>
          ) : (
            (script.data.files ?? []).map((f) => (
              <CodeBlock
                key={f.path}
                ai={!target.reused_script}
                file={`${f.path} · ${target.reused_script ? t('검증된 스크립트 재사용') : (target.attempt ?? 0) > 1 ? t('AI 수정 {n}회차', { n: target.attempt ?? 0 }) : t('AI 생성')}`}
                code={f.content}
              />
            ))
          )}
        </Panel>
      </div>

      {approvable && (
        <div className="page__actions">
          <Button variant="secondary" onClick={() => navigate(paths.approve(projectId, d.id))}>
            {t('변경 사항 확인하기')}
          </Button>
        </div>
      )}
    </div>
  )
}

export default GeneratePage
