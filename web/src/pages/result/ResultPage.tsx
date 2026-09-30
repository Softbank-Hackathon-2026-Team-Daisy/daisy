import { useState } from 'react'
import { useNavigate, useParams } from 'react-router'
import { api } from '../../api/endpoints.ts'
import { deploymentStatus, targetStatus } from '../../api/status.ts'
import type { Deployment, DeploymentTarget } from '../../api/types.ts'
import { useResource } from '../../api/useResource.ts'
import Button from '../../components/Button.tsx'
import ParityTable, { type ParityRow } from '../../components/ParityTable.tsx'
import PageHeader from '../../components/PageHeader.tsx'
import ResultCard from '../../components/ResultCard.tsx'
import StatusBadge from '../../components/StatusBadge.tsx'
import Stepper from '../../components/Stepper.tsx'
import Toast from '../../components/Toast.tsx'
import { paths } from '../../paths.ts'
import { shortCommit } from '../../utils/format.ts'
import { names } from '../flow.ts'
import { ErrorBlock, LoadingBlock } from '../Loading.tsx'
import '../page.css'

// W-08 배포 결과 (STEP 6) — 환경별 URL · 헬스, 동일성 검증(이식성 데모 포인트)
function ResultPage() {
  const { deploymentId = '' } = useParams()
  const deployment = useResource(() => api.getDeployment(deploymentId), [deploymentId])
  if (deployment.error) return <ErrorBlock error={deployment.error} />
  if (!deployment.data) return <LoadingBlock />
  return <ResultView d={deployment.data} />
}

function ResultView({ d }: { d: Deployment }) {
  const navigate = useNavigate()
  const { projectId = '' } = useParams()
  const [toast, setToast] = useState<string | null>(null)
  const status = deploymentStatus(d.state, d.kind)
  const ok = d.targets.filter((t) => t.state === 'succeeded')
  const bad = d.targets.filter((t) => t.state === 'failed')
  const base = ok[0]
  const matched = ok.filter((t) => t.image_digest && t.image_digest === base?.image_digest).length

  const copy = async (url: string) => {
    await navigator.clipboard?.writeText(url)
    setToast('URL을 복사했어요')
  }

  const retry = async (t: DeploymentTarget) => {
    const next = await api.createDeployment(projectId, d.commit, [t.target_id])
    navigate(paths.generate(projectId, next.id), { state: { transition: 'l02' } })
  }

  const values = (pick: (t: DeploymentTarget) => string | null) => Object.fromEntries(d.targets.map((t) => [t.target_id, pick(t)]))
  const rows: ParityRow[] = [
    { label: '이미지 digest', values: values((t) => t.image_digest ?? null), failed: d.targets.filter((t) => base && t.image_digest && t.image_digest !== base.image_digest).map((t) => t.target_id) },
    { label: '커밋', values: values(() => shortCommit(d.commit)) },
    { label: '앱 버전', values: values(() => d.version) },
    { label: '헬스체크', values: values((t) => (t.state === 'succeeded' ? '200 OK' : t.state === 'failed' ? (t.health_summary ?? '실패') : null)), failed: bad.map((t) => t.target_id) },
  ]

  const description =
    bad.length === 0
      ? '모든 환경이 같은 이미지로 떠 있는지 확인해요.'
      : ok.length === 0
        ? '모든 환경이 실패했어요. 원인을 확인하고 다시 시도해 주세요.'
        : `${names(ok)}는 성공, ${names(bad)}는 ${bad[0].step === 'health_check' ? '헬스체크에서' : 'apply에서'} 실패했어요. 성공한 환경끼리 같은 이미지인지 확인해요.`

  return (
    <div className="page">
      <Stepper current={6} />
      <PageHeader overline="Step 6" title="배포 결과" badge={<StatusBadge tone={status.tone}>{status.label}</StatusBadge>} description={description} />

      <div className="page__row page__row--3">
        {d.targets.map((t) => {
          const s = targetStatus(t.state)
          const failed = t.state === 'failed'
          return (
            <ResultCard
              key={t.target_id}
              env={t.type}
              tone={s.tone}
              label={s.label}
              url={t.url}
              health={
                failed ? (
                  <button type="button" className="t-body-sm" style={{ padding: 0, border: 0, background: 'none', color: 'var(--color-danger)', cursor: 'pointer' }} onClick={() => navigate(paths.progress(projectId, d.id))}>
                    {t.step === 'health_check' ? '헬스체크 실패' : 'apply 실패'} · 원인 보기
                  </button>
                ) : (
                  <span className="t-muted">{t.health_summary ?? '—'}</span>
                )
              }
              actions={
                <>
                  {failed ? (
                    <Button variant="outline" onClick={() => void retry(t)}>
                      다시 시도
                    </Button>
                  ) : (
                    <Button variant="outline" disabled={!t.url} onClick={() => t.url && window.open(t.url, '_blank', 'noopener')}>
                      열기
                    </Button>
                  )}
                  <Button variant="ghost" disabled={!t.url} onClick={() => t.url && void copy(t.url)}>
                    URL 복사
                  </Button>
                </>
              }
            />
          )
        })}
      </div>

      <ParityTable envs={d.targets.map((t) => ({ id: t.target_id, type: t.type }))} rows={rows} matched={matched} mismatch={rows[0].failed!.length > 0} />

      {toast && <Toast type="success" title={toast} onClose={() => setToast(null)} />}

      <div className="page__actions">
        <Button variant="outline" onClick={() => navigate(paths.history(projectId))}>
          이력 보기
        </Button>
        <Button variant="ghost" onClick={() => setToast('QR 공유는 Mac 앱 · TestFlight 링크가 정해지면 열어요')}>
          QR로 공유
        </Button>
      </div>
    </div>
  )
}

export default ResultPage
