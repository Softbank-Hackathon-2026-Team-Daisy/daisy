import { useNavigate, useParams } from 'react-router'
import { api } from '../../api/endpoints.ts'
import { deploymentStatus } from '../../api/status.ts'
import type { Deployment, TargetStatus } from '../../api/types.ts'
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
import { relativeTime, shortCommit } from '../../utils/format.ts'
import { ErrorBlock, LoadingBlock } from '../Loading.tsx'
import '../page.css'
import './OverviewPage.css'

// W-01 개요 — 지금 어느 환경에 어떤 버전이 떠 있는지, 다음에 할 일이 뭔지
function OverviewPage() {
  const { projectId = '' } = useParams()
  const navigate = useNavigate()
  const status = useResource(() => api.getTargetsStatus(projectId), [projectId], 5000)
  const runs = useResource(() => api.listDeployments(projectId), [projectId], 5000)

  if (status.error) return <ErrorBlock error={status.error} />
  if (!status.data || !runs.data) return <LoadingBlock />

  const targets = status.data
  const deployments = runs.data.items
  const pending = deployments.find((d) => d.state === 'awaiting_approval')
  const recent = deployments.filter((d) => d.state !== 'awaiting_approval').slice(0, 3)
  const image = targets.find((t) => t.current)?.current?.image

  return (
    <div className="page">
      <PageHeader overline="Overview" title="개요" description={`${projectLabel(deployments)}가 지금 어느 환경에 어떤 버전으로 떠 있는지, 다음에 할 일이 뭔지 봐요.`} />

      <div className="page__row page__row--main-side">
        <Panel title="환경별 현재 버전" aside={image && <span className="t-mono-sm t-muted">{shortImage(image)}</span>}>
          {targets.length === 0 ? (
            <EmptyState icon="server" title="아직 배포한 환경이 없어요" description="새 배포로 첫 환경을 올려 보세요" />
          ) : (
            <div>
              {targets.map((t) => (
                <div className="env-row" key={t.target_id}>
                  <span className="env-row__tag">
                    <EnvTag env={t.type} />
                  </span>
                  <span className="t-mono">{t.current ? shortCommit(t.current.commit) : '—'}</span>
                  <span className="t-body-sm t-muted">{t.current ? relativeTime(t.current.deployed_at) : ''}</span>
                  <span className="env-row__url t-mono-sm t-muted">{t.url ?? '—'}</span>
                  <StatusBadge tone={t.health === 'healthy' ? 'success' : t.health === 'unhealthy' ? 'failed' : 'queued'}>
                    {t.health === 'healthy' ? '정상' : t.health === 'unhealthy' ? '이상' : '확인 전'}
                  </StatusBadge>
                </div>
              ))}
            </div>
          )}
          <Parity targets={targets} compact />
        </Panel>

        <Panel title="지금 할 일">
          {pending ? (
            <>
              <div className="page__list">
                <RunListItem tone="queued" label="승인 대기" commit={pending.commit} message={pending.commit_message ?? ''} author={pending.created_by} at={pending.created_at} />
              </div>
              <Alert type="info" title="검증 통과 · 승인만 남았어요">
                {reuseNote(pending)}
              </Alert>
              <div className="overview__grow" />
              {/* 노란 버튼은 W-06 전용이라 여기는 Secondary */}
              <Button variant="secondary" onClick={() => navigate(paths.approve(projectId, pending.id))}>
                plan 보고 승인하기
              </Button>
            </>
          ) : (
            <EmptyState icon="check" title="지금 할 일이 없어요" description="승인을 기다리는 배포가 없어요" />
          )}
        </Panel>
      </div>

      <Parity targets={targets} />

      <Panel
        title="최근 실행"
        aside={
          <Button variant="ghost" onClick={() => navigate(paths.history(projectId))}>
            이력 전체 보기
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
                label={d.state === 'succeeded' ? '배포 완료' : d.state === 'failed' ? '중단' : s.label}
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
  const live = targets.filter((t) => t.current)
  const base = live[0]
  const same = live.filter((t) => t.image_digest && t.image_digest === base?.image_digest).length
  if (compact) {
    return (
      <p className="overview__parity">
        <StatusBadge tone={same === targets.length ? 'success' : 'warning'}>{`${same}/${targets.length} 일치`}</StatusBadge>
        <span className="t-body-sm t-muted">{same === targets.length ? '세 환경 모두 같은 이미지 digest예요' : '이미지 digest가 다른 환경이 있어요'}</span>
      </p>
    )
  }
  const values = (pick: (t: TargetStatus) => string | null): Record<string, string | null> =>
    Object.fromEntries(targets.map((t) => [t.target_id, pick(t)]))
  const differs = (pick: (t: TargetStatus) => string | null) =>
    targets.filter((t) => base && pick(t) !== null && pick(t) !== pick(base)).map((t) => t.target_id)
  const rows: ParityRow[] = [
    { label: '이미지 digest', values: values((t) => t.image_digest ?? null), failed: differs((t) => t.image_digest ?? null) },
    { label: '커밋', values: values((t) => (t.current ? shortCommit(t.current.commit) : null)), failed: differs((t) => t.current?.commit ?? null) },
    { label: '헬스체크', values: values((t) => (t.health === 'healthy' ? '200 OK' : t.health === 'unhealthy' ? '실패' : null)), failed: targets.filter((t) => t.health === 'unhealthy').map((t) => t.target_id) },
  ]
  return <ParityTable envs={targets.map((t) => ({ id: t.target_id, type: t.type }))} rows={rows} matched={same} />
}

function reuseNote(d: Deployment) {
  const reused = d.targets.filter((t) => t.reused_script)
  if (reused.length === 0) return '모든 환경의 validate · plan · 위험 설정 검사를 통과했어요.'
  const names = reused.map((t) => ({ onprem: '온프레미스', aws: 'AWS', gcp: 'GCP' })[t.type]).join(' · ')
  return `${names}는 검증된 스크립트 재사용이라 AI 호출 0회예요.`
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
