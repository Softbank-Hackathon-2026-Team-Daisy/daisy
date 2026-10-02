import { useNavigate, useParams } from 'react-router'
import { api, isMocked } from '../../api/endpoints.ts'
import { deploymentStatus } from '../../api/status.ts'
import type { Deployment, TargetStatus } from '../../api/types.ts'
import { pollFor, useProjectLive } from '../../api/projectLive.ts'
import { useResource } from '../../api/useResource.ts'
import Alert from '../../components/Alert.tsx'
import Button from '../../components/Button.tsx'
import EmptyState from '../../components/EmptyState.tsx'
import EnvTag from '../../components/EnvTag.tsx'
import PageHeader from '../../components/PageHeader.tsx'
import Panel from '../../components/Panel.tsx'
import ParityTable, { type ParityRow } from '../../components/ParityTable.tsx'
import RunListItem from '../../components/RunListItem.tsx'
import StatusBadge from '../../components/StatusBadge.tsx'
import { paths } from '../../paths.ts'
import { t } from '../../i18n/index.ts'
import { relativeTime, shortCommit } from '../../utils/format.ts'
import { ErrorBlock, LoadingBlock } from '../Loading.tsx'
import '../page.css'
import './OverviewPage.css'

// W-01 개요 — 지금 어느 환경에 어떤 버전이 떠 있는지, 다음에 할 일이 뭔지
function OverviewPage() {
  const { projectId = '' } = useParams()
  const navigate = useNavigate()
  const { state: live, tick } = useProjectLive()
  const status = useResource(() => api.getTargetsStatus(projectId), [projectId, tick], pollFor(live))
  const runs = useResource(() => api.listDeployments(projectId), [projectId, tick], pollFor(live))

  if (status.error) return <ErrorBlock error={status.error} />
  if (!status.data || !runs.data) return <LoadingBlock />

  const targets = status.data.items
  const deployments = runs.data.items
  const pending = deployments.find((d) => d.state === 'awaiting_approval')
  const recent = deployments.filter((d) => d.state !== 'awaiting_approval').slice(0, 3)
  const image = targets.find((tg) => tg.current)?.current?.image

  return (
    <div className="page">
      <PageHeader mock={isMocked('getTargetsStatus', 'listDeployments')} overline="Overview" title={t('개요')} description={t('{name}가 지금 어느 환경에 어떤 버전으로 떠 있는지, 다음에 할 일이 뭔지 봐요.', { name: projectLabel(deployments) })} />

      <div className="page__row page__row--main-side">
        <Panel title={t('환경별 현재 버전')} aside={image && <span className="t-mono-sm t-muted">{shortImage(image)}</span>}>
          {targets.length === 0 ? (
            <EmptyState icon="server" title={t('아직 연결한 환경이 없어요')} description={t('환경을 연결하면 여기에 현재 버전이 보여요')} />
          ) : (
            <div>
              {targets.map((tg) => (
                <div className="env-row" key={tg.target_id}>
                  <span className="env-row__tag">
                    <EnvTag env={tg.type} />
                  </span>
                  {/* current가 null이면 "확인된 현재 배포 없음" — 배포를 안 했다는 뜻이 아니에요 (#42) */}
                  <span className="t-mono">{tg.current ? shortCommit(tg.current.commit) : '—'}</span>
                  <span className="t-body-sm t-muted">{tg.current ? relativeTime(tg.current.deployed_at) : t('확인된 배포 없음')}</span>
                  <span className="env-row__url t-mono-sm t-muted">{tg.url ?? '—'}</span>
                  <StatusBadge tone={tg.health === 'healthy' ? 'success' : tg.health === 'unhealthy' ? 'failed' : 'queued'}>
                    {tg.health === 'healthy' ? t('정상') : tg.health === 'unhealthy' ? t('이상') : t('확인 전')}
                  </StatusBadge>
                </div>
              ))}
            </div>
          )}
          <Parity targets={targets} compact />
        </Panel>

        <Panel title={t('지금 할 일')}>
          {pending ? (
            <>
              <div className="page__list">
                <RunListItem tone="queued" label={t('승인 대기')} commit={pending.commit} message={pending.commit_message ?? ''} author={pending.created_by} at={pending.created_at} />
              </div>
              <Alert type="info" title={t('검증 통과 · 승인만 남았어요')}>
                {reuseNote(pending)}
              </Alert>
              <div className="overview__grow" />
              {/* 노란 버튼은 W-06 전용이라 여기는 Secondary */}
              <Button variant="secondary" onClick={() => navigate(paths.approve(projectId, pending.id))}>
                {t('plan 보고 승인하기')}
              </Button>
            </>
          ) : (
            <EmptyState icon="check" title={t('지금 할 일이 없어요')} description={t('승인을 기다리는 배포가 없어요')} />
          )}
        </Panel>
      </div>

      <Parity targets={targets} />

      <Panel
        title={t('최근 실행')}
        aside={
          <Button variant="ghost" onClick={() => navigate(paths.history(projectId))}>
            {t('이력 전체 보기')}
          </Button>
        }
      >
        <div className="page__list">
          {recent.map((d) => {
            const s = deploymentStatus(d.state, d.kind)
            return (
              <RunListItem
                key={d.id}
                tone={s.tone}
                label={d.state === 'succeeded' ? t('배포 완료') : d.state === 'failed' ? t('중단') : s.label}
                commit={d.commit}
                message={d.commit_message ?? ''}
                author={d.created_by}
                at={d.created_at}
                to={paths.result(projectId, d.id)}
              />
            )
          })}
        </div>
      </Panel>
    </div>
  )
}

// 동일성 검증 — compact면 요약 한 줄, 아니면 표 (W-08과 같은 컴포넌트)
function Parity({ targets, compact }: { targets: TargetStatus[]; compact?: boolean }) {
  const live = targets.filter((tg) => tg.current)
  const base = live[0]
  const same = live.filter((tg) => tg.image_digest && tg.image_digest === base?.image_digest).length
  const known = targets.filter((tg) => tg.image_digest).length
  if (compact) {
    // digest를 하나도 못 받았으면 "다르다"가 아니라 "확인 전"이에요 (인프라 apply 결과 전에는 null, #38)
    if (known === 0) {
      return (
        <p className="overview__parity">
          <StatusBadge tone="queued">{t('확인 전')}</StatusBadge>
          <span className="t-body-sm t-muted">{t('아직 환경별 이미지 digest를 받지 못했어요')}</span>
        </p>
      )
    }
    return (
      <p className="overview__parity">
        <StatusBadge tone={same === targets.length ? 'success' : 'warning'}>{t('{same}/{total} 일치', { same, total: targets.length })}</StatusBadge>
        <span className="t-body-sm t-muted">{same === targets.length ? t('{n}개 환경 모두 같은 이미지 digest예요', { n: targets.length }) : t('이미지 digest가 다르거나 확인 전인 환경이 있어요')}</span>
      </p>
    )
  }
  const values = (pick: (tg: TargetStatus) => string | null): Record<string, string | null> =>
    Object.fromEntries(targets.map((tg) => [tg.target_id, pick(tg)]))
  const differs = (pick: (tg: TargetStatus) => string | null) =>
    targets.filter((tg) => base && pick(tg) !== null && pick(tg) !== pick(base)).map((tg) => tg.target_id)
  const rows: ParityRow[] = [
    { label: t('이미지 digest'), values: values((tg) => tg.image_digest ?? null), failed: differs((tg) => tg.image_digest ?? null) },
    { label: t('커밋'), values: values((tg) => (tg.current ? shortCommit(tg.current.commit) : null)), failed: differs((tg) => tg.current?.commit ?? null) },
    { label: t('헬스체크'), values: values((tg) => tg.health_summary ?? (tg.health === 'healthy' ? t('정상') : tg.health === 'unhealthy' ? t('실패') : null)), failed: targets.filter((tg) => tg.health === 'unhealthy').map((tg) => tg.target_id) },
  ]
  return <ParityTable envs={targets.map((tg) => ({ id: tg.target_id, type: tg.type }))} rows={rows} matched={same} unknown={known === 0} />
}

function reuseNote(d: Deployment) {
  const reused = d.targets.filter((tg) => tg.reused_script)
  if (reused.length === 0) return t('모든 환경의 validate · plan · 위험 설정 검사를 통과했어요.')
  const names = reused.map((tg) => ({ onprem: t('온프레미스'), aws: 'AWS', gcp: 'GCP' })[tg.type]).join(' · ')
  return t('{names}는 검증된 스크립트 재사용이라 AI 호출 0회예요.', { names })
}

// MOCK: 프로젝트 이름은 A-01 목록에서 가져와요. 지금은 목업 이름
function projectLabel(deployments: Deployment[]) {
  return deployments[0]?.project_id === 'prj_msa' ? 'sample-msa' : 'sample-monolith'
}

function shortImage(image: string) {
  const [repo, tag] = image.split(':')
  const name = repo.split('/').pop()
  return `${repo.split('/')[0]}/…/${name}:${tag}`
}

export default OverviewPage
