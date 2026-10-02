import { useState } from 'react'
import { useNavigate, useParams } from 'react-router'
import { useAuth } from '../../api/auth.ts'
import { ApiError, errorMessage, newIdempotencyKey } from '../../api/client.ts'
import { api, isMocked } from '../../api/endpoints.ts'
import type { Deployment, Plan, PlanDetail } from '../../api/types.ts'
import { useDeploymentLive } from '../../api/useRealtime.ts'
import { useResource } from '../../api/useResource.ts'
import Alert from '../../components/Alert.tsx'
import ApprovalBar from '../../components/ApprovalBar.tsx'
import Button from '../../components/Button.tsx'
import CodeBlock from '../../components/CodeBlock.tsx'
import EnvStatusRow from '../../components/EnvStatusRow.tsx'
import Input from '../../components/Input.tsx'
import PageHeader from '../../components/PageHeader.tsx'
import Panel from '../../components/Panel.tsx'
import ResourceDiffRow from '../../components/ResourceDiffRow.tsx'
import Stepper from '../../components/Stepper.tsx'
import Tabs from '../../components/Tabs.tsx'
import { t } from '../../i18n/index.ts'
import { paths } from '../../paths.ts'
import { shortCommit, won } from '../../utils/format.ts'
import { envName, names } from '../flow.ts'
import { ErrorBlock, LoadingBlock } from '../Loading.tsx'
import '../page.css'

// W-06 변경 사항 확인 후 승인 (STEP 5). 승인하면 선택한 모든 환경에 동시에 적용해요 (API W-01)
function ApprovePage() {
  const { projectId = '', deploymentId = '' } = useParams()
  // 삭제 확인 단어는 프로젝트 이름(A-12) — 서버가 승인 대기를 만들 때 고정한 이름과 비교해요 (#49 리뷰)
  const project = useResource(() => api.getProject(projectId), [projectId])
  // plan.ready · plan.stale · approval.* 이벤트가 오면 세 개를 다시 불러요 (다른 사람이 앱에서 먼저 승인한 경우 등)
  const live = useDeploymentLive(deploymentId)
  const deployment = useResource(() => api.getDeployment(deploymentId), [deploymentId, live.tick])
  const plan = useResource(() => api.getPlan(deploymentId), [deploymentId, live.tick])
  const detail = useResource(() => api.getPlanDetail(deploymentId), [deploymentId, live.tick])

  const error = deployment.error ?? plan.error ?? detail.error
  if (error) return <ErrorBlock error={error} />
  if (!deployment.data || !plan.data || !detail.data) return <LoadingBlock />
  return (
    <ApproveView
      key={deployment.data.id}
      d={deployment.data}
      plan={plan.data}
      detail={detail.data}
      projectName={project.data?.name ?? ''}
      reload={deployment.reload}
    />
  )
}

function ApproveView({ d, plan, detail, projectName, reload }: { d: Deployment; plan: Plan; detail: PlanDetail[]; projectName: string; reload: () => void }) {
  const navigate = useNavigate()
  const { projectId = '' } = useParams()
  const { role } = useAuth()
  // 이미 승인했는데 apply가 아직 시작 안 된 대상은 다시 승인하지 않아요 (#56 approval_state, #49 리뷰)
  const approvedWaiting = d.targets.filter((tg) => tg.state === 'awaiting_approval' && tg.approval_state === 'approved')
  const approvable = d.targets.filter((tg) => tg.state === 'awaiting_approval' && tg.approval_state !== 'approved')
  const [tab, setTab] = useState(approvable[1]?.target_id ?? approvable[0]?.target_id ?? d.targets[0].target_id)
  const [confirm, setConfirm] = useState('')
  const [pending, setPending] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const planOf = (id: string) => plan.targets.find((p) => p.target_id === id)
  const sum = approvable.reduce(
    (acc, tg) => {
      const c = planOf(tg.target_id)?.counts
      return c ? { create: acc.create + c.create, update: acc.update + c.update, delete: acc.delete + c.delete } : acc
    },
    { create: 0, update: 0, delete: 0 },
  )
  const hasDelete = approvable.some((tg) => planOf(tg.target_id)?.has_delete)
  const risks = approvable.flatMap((tg) => planOf(tg.target_id)?.risks ?? [])
  // 삭제가 포함되면 프로젝트 이름을 입력해야 승인할 수 있어요 (서버도 confirm_text를 검증해요)
  const confirmWord = projectName
  // 이름을 아직 못 불러왔으면 확인을 통과시키지 않아요
  const needsConfirm = hasDelete && (!confirmWord || confirm !== confirmWord)
  const viewer = role === 'viewer'
  const current = d.targets.find((tg) => tg.target_id === tab) ?? d.targets[0]
  const currentDetail = detail.find((x) => x.target_id === current.target_id)
  const currentPlan = planOf(current.target_id)

  const decide = async (decision: 'approve' | 'reject') => {
    if (pending) return
    setPending(true)
    setError(null)
    try {
      // 화면에 보인 승인 대기 환경 중 승인 ID가 있는 것만 보내요 (만료된 승인은 서버가 빼서 줘요, #46)
      const items = approvable.flatMap((tg) => {
        const a = d.pending_approvals.find((x) => x.target_id === tg.target_id)
        return a ? [{ target_id: tg.target_id, approval_id: a.approval_id }] : []
      })
      // 승인 ID가 하나도 없으면(만료) 서버가 400을 줘요 → 보내지 않고 최신 상태를 다시 불러와요
      if (items.length === 0) {
        setError(t('승인할 수 있는 plan이 없어요. 만료됐을 수 있어서 최신 상태를 다시 불러왔어요.'))
        reload()
        setPending(false)
        return
      }
      await api.approve(d.id, decision, hasDelete ? confirm : undefined, items, newIdempotencyKey())
      if (decision === 'approve') navigate(paths.progress(projectId, d.id), { state: { transition: 'l03' } })
      // Q1(거절하면 어디로)이 정해지기 전까지는 개요로 돌아가요
      else navigate(paths.overview(projectId))
    } catch (e) {
      if (e instanceof ApiError && e.status === 409) {
        setError(t('승인 상태가 바뀌어서 최신 상태를 다시 불러왔어요. 다시 확인해 주세요.'))
        reload()
      } else {
        setError(errorMessage(e, t('처리하지 못했어요')))
      }
      setPending(false)
    }
  }

  // 한 환경이 실패해도 나머지가 승인 대기면 승인할 수 있어요 (Q7)
  if (approvable.length === 0) {
    return (
      <div className="page">
        <Stepper current={5} />
        <PageHeader mock={isMocked('getDeployment', 'getPlan', 'getPlanDetail', 'approve')} overline="Step 5" title={t('변경 사항 확인 후 승인')} />
        {approvedWaiting.length > 0 ? (
          <Alert type="success" title={t('승인 완료 · 실행 대기')}>
            {t('{names} 승인을 받았어요. 곧 배포를 시작해요.', { names: names(approvedWaiting) })}
          </Alert>
        ) : (
          <Alert type="info" title={t('승인을 기다리는 plan이 없어요')}>
            {t('이미 처리됐거나 아직 검증 중이에요.')}
          </Alert>
        )}
        <div className="page__actions">
          <Button variant="secondary" onClick={() => navigate(paths.progress(projectId, d.id))}>
            {t('배포 진행 보기')}
          </Button>
        </div>
      </div>
    )
  }

  return (
    <div className="page">
      <Stepper current={5} />
      <PageHeader mock={isMocked('getDeployment', 'getPlan', 'getPlanDetail', 'approve')} overline="Step 5" title={t('변경 사항 확인 후 승인')} description={t('환경별 plan 결과예요. 승인하면 선택한 모든 환경에 동시에 적용해요.')} />

      <Panel title={t('환경별 요약')}>
        {d.targets.map((tg) => {
          const p = planOf(tg.target_id)
          if (tg.state === 'awaiting_approval' && tg.approval_state === 'approved')
            return <EnvStatusRow key={tg.target_id} env={tg.type} note={t('승인 완료 · 실행 대기')} tone="success" label={t('승인됨')} />
          if (tg.state === 'failed') return <EnvStatusRow key={tg.target_id} env={tg.type} note={tg.attempt ? t('{n}회 실패 · 이번 승인에서 빠져요', { n: tg.attempt }) : t('실패 · 이번 승인에서 빠져요')} tone="failed" label={t('실패')} />
          const c = p?.counts
          const note = c
            ? t('리소스 +{create} ~{update} −{delete} · {summary}', {
                create: c.create,
                update: c.update,
                delete: c.delete,
                summary: p?.summary ?? t('위험 설정 {n}건', { n: p?.risks.length ?? 0 }),
              })
            : '—'
          return <EnvStatusRow key={tg.target_id} env={tg.type} note={note} tone="success" label={t('검증 통과')} />
        })}
      </Panel>

      <Tabs label={t('환경별 plan')} value={current.target_id} onChange={setTab} items={d.targets.map((tg) => ({ id: tg.target_id, label: envName(tg), env: tg.type }))} />

      <Panel title={t('{env} plan', { env: envName(current) })}>
        {currentDetail ? (
          <>
            {currentDetail.resources.map((r) => (
              <ResourceDiffRow
                key={r.address}
                action={r.action}
                address={r.address}
                cost={r.monthly_cost_krw === undefined ? undefined : r.monthly_cost_krw === 0 ? '₩0' : t('+{cost}/월', { cost: won(r.monthly_cost_krw) })}
              />
            ))}
            {currentPlan && currentPlan.risks.length > 0 ? (
              currentPlan.risks.map((r) => (
                <Alert key={r.rule + r.resource} type="warning" title={t('위험 설정 · {level}', { level: r.level })}>
                  {r.message} ({r.resource})
                </Alert>
              ))
            ) : (
              <Alert type="success" title={t('사전 검증 통과')}>
                {t('validate · plan · 위험 설정 검사를 모두 통과했어요.')}
              </Alert>
            )}
            {currentDetail.plan_text && <CodeBlock file={`${current.type} · terraform plan`} code={currentDetail.plan_text} />}
          </>
        ) : (
          <p className="t-muted">{t('이 환경은 plan이 없어요.')}</p>
        )}
      </Panel>

      {hasDelete && (
        <Alert type="danger" title={t('삭제되는 리소스가 있어요')}>
          <label style={{ display: 'flex', flexDirection: 'column', gap: 6, marginTop: 6 }}>
            {t('확인을 위해 프로젝트 이름({name})을 입력해 주세요.', { name: confirmWord })}
            <Input value={confirm} onChange={(e) => setConfirm(e.target.value)} placeholder={confirmWord} />
          </label>
        </Alert>
      )}
      {error && <Alert type="danger" title={t('처리하지 못했어요')}>{error}</Alert>}

      <ApprovalBar
        title={t('{n}개 환경 · 리소스 +{create} ~{update} −{delete}', { n: approvable.length, create: sum.create, update: sum.update, delete: sum.delete })}
        meta={t('검증 통과 {ok}/{total} · 이미지 {commit} · 위험 설정 {risks}건 · AI 비용 {cost}', {
          ok: approvable.length,
          total: d.targets.length,
          commit: shortCommit(d.commit),
          risks: risks.length,
          cost: won(plan.ai_usage.cost_krw) + (plan.ai_usage.exchange_rate ? ' ' + t('(추정, 환율 {rate}원)', { rate: plan.ai_usage.exchange_rate.toLocaleString('ko-KR') }) : ''),
        })}
        disabled={viewer || needsConfirm || approvable.length === 0}
        pending={pending}
        note={viewer && <p className="t-body-sm" style={{ color: 'var(--color-warning)' }}>{t('읽기 전용 계정이라 승인할 수 없어요.')}</p>}
        onApprove={() => void decide('approve')}
        onReject={() => void decide('reject')}
      />
    </div>
  )
}

export default ApprovePage
