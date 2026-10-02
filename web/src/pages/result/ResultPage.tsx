import { useState } from 'react'
import { useNavigate, useParams } from 'react-router'
import { useAuth } from '../../api/auth.ts'
import { api, isMocked } from '../../api/endpoints.ts'
import { deploymentStatus, targetStatus } from '../../api/status.ts'
import type { Deployment, DeploymentTarget } from '../../api/types.ts'
import { useAction } from '../../api/useAction.ts'
import { useDeploymentLive } from '../../api/useRealtime.ts'
import { useResource } from '../../api/useResource.ts'
import Alert from '../../components/Alert.tsx'
import Button from '../../components/Button.tsx'
import ParityTable, { type ParityRow } from '../../components/ParityTable.tsx'
import PageHeader from '../../components/PageHeader.tsx'
import ResultCard from '../../components/ResultCard.tsx'
import StatusBadge from '../../components/StatusBadge.tsx'
import Stepper from '../../components/Stepper.tsx'
import Toast from '../../components/Toast.tsx'
import { t } from '../../i18n/index.ts'
import { paths } from '../../paths.ts'
import { shortCommit } from '../../utils/format.ts'
import { failedStep, names, versionLabel } from '../flow.ts'
import { ErrorBlock, LoadingBlock } from '../Loading.tsx'
import ReadOnlyNote from '../ReadOnlyNote.tsx'
import '../page.css'

// W-08 배포 결과 (STEP 6) — 환경별 URL · 헬스, 동일성 검증(이식성 데모 포인트)
function ResultPage() {
  const { deploymentId = '' } = useParams()
  const live = useDeploymentLive(deploymentId)
  const deployment = useResource(() => api.getDeployment(deploymentId), [deploymentId, live.tick])
  if (deployment.error) return <ErrorBlock error={deployment.error} />
  if (!deployment.data) return <LoadingBlock />
  return <ResultView d={deployment.data} />
}

function ResultView({ d }: { d: Deployment }) {
  const navigate = useNavigate()
  const { projectId = '' } = useParams()
  const [toast, setToast] = useState<string | null>(null)
  const { run, pending, error: retryError } = useAction()
  const viewer = useAuth().role === 'viewer'
  const status = deploymentStatus(d.state, d.kind)
  const ok = d.targets.filter((tg) => tg.state === 'succeeded')
  const bad = d.targets.filter((tg) => tg.state === 'failed')
  const base = ok[0]
  const matched = ok.filter((tg) => tg.image_digest && tg.image_digest === base?.image_digest).length

  const copy = async (url: string) => {
    await navigator.clipboard?.writeText(url)
    setToast(t('URL을 복사했어요'))
  }

  // 실패한 환경만 새 배포로 다시 시도 — POST /deployments/{id}/retry (10/2 확정)
  const retry = async (tg: DeploymentTarget) => {
    const next = await run((key) => api.retry(d.id, [tg.target_id], key), t('다시 시도하지 못했어요'))
    if (next) navigate(paths.generate(projectId, next.id), { state: { transition: 'l02' } })
  }

  const values = (pick: (tg: DeploymentTarget) => string | null) => Object.fromEntries(d.targets.map((tg) => [tg.target_id, pick(tg)]))
  const rows: ParityRow[] = [
    { label: t('이미지 digest'), values: values((tg) => tg.image_digest ?? null), failed: d.targets.filter((tg) => base && tg.image_digest && tg.image_digest !== base.image_digest).map((tg) => tg.target_id) },
    { label: t('커밋'), values: values(() => shortCommit(d.commit)) },
    { label: t('배포 버전'), values: values(() => versionLabel(d)) },
    { label: t('헬스체크'), values: values((tg) => (tg.state === 'succeeded' ? (tg.health_summary ?? '—') : tg.state === 'failed' ? (tg.health_summary ?? t('실패')) : null)), failed: bad.map((tg) => tg.target_id) },
  ]

  const description =
    bad.length === 0
      ? t('모든 환경이 같은 이미지로 떠 있는지 확인해요.')
      : ok.length === 0
        ? t('모든 환경이 실패했어요. 원인을 확인하고 다시 시도해 주세요.')
        : failedStep(bad[0])
          ? t('{ok}는 성공, {bad}는 {step}에서 실패했어요. 성공한 환경끼리 같은 이미지인지 확인해요.', { ok: names(ok), bad: names(bad), step: failedStep(bad[0])! })
          : t('{ok}는 성공, {bad}는 실패했어요. 성공한 환경끼리 같은 이미지인지 확인해요.', { ok: names(ok), bad: names(bad) })

  return (
    <div className="page">
      <Stepper current={6} />
      <PageHeader mock={isMocked('getDeployment', 'retry')} overline="Step 6" title={t('배포 결과')} badge={<StatusBadge tone={status.tone}>{status.label}</StatusBadge>} description={description} />

      <div className="page__row page__row--3">
        {d.targets.map((tg) => {
          const s = targetStatus(tg.state)
          const failed = tg.state === 'failed'
          return (
            <ResultCard
              key={tg.target_id}
              env={tg.type}
              tone={s.tone}
              label={s.label}
              url={tg.url}
              health={
                failed ? (
                  <button type="button" className="t-body-sm" style={{ padding: 0, border: 0, background: 'none', color: 'var(--color-danger)', cursor: 'pointer' }} onClick={() => navigate(paths.progress(projectId, d.id))}>
                    {failedStep(tg) ? t('{step} 실패 · 원인 보기', { step: failedStep(tg)! }) : t('실패 · 원인 보기')}
                  </button>
                ) : (
                  <span className="t-muted">{tg.health_summary ?? '—'}</span>
                )
              }
              actions={
                <>
                  {failed ? (
                    <Button variant="outline" disabled={viewer || pending} onClick={() => void retry(tg)}>
                      {pending ? t('시작하는 중…') : t('다시 시도')}
                    </Button>
                  ) : (
                    <Button variant="outline" disabled={!tg.url} onClick={() => tg.url && window.open(tg.url, '_blank', 'noopener')}>
                      {t('열기')}
                    </Button>
                  )}
                  <Button variant="ghost" disabled={!tg.url} onClick={() => tg.url && void copy(tg.url)}>
                    {t('URL 복사')}
                  </Button>
                </>
              }
            />
          )
        })}
      </div>

      <ParityTable envs={d.targets.map((tg) => ({ id: tg.target_id, type: tg.type }))} rows={rows} matched={matched} mismatch={rows[0].failed!.length > 0} />

      {retryError && <Alert type="danger" title={t('다시 시도하지 못했어요')}>{retryError}</Alert>}
      {viewer && bad.length > 0 && <ReadOnlyNote message={t('읽기 전용 계정이라 다시 시도할 수 없어요.')} />}

      {toast && <Toast type="success" title={toast} onClose={() => setToast(null)} />}

      <div className="page__actions">
        <Button variant="outline" onClick={() => navigate(paths.history(projectId))}>
          {t('이력 보기')}
        </Button>
        <Button variant="ghost" onClick={() => setToast(t('QR 공유는 Mac 앱 · TestFlight 링크가 정해지면 열어요'))}>
          {t('QR로 공유')}
        </Button>
      </div>
    </div>
  )
}

export default ResultPage
