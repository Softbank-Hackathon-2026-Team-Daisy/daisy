import { Navigate, useParams } from 'react-router'
import { api, isMocked } from '../../api/endpoints.ts'
import type { Deployment } from '../../api/types.ts'
import { useResource } from '../../api/useResource.ts'
import EmptyState from '../../components/EmptyState.tsx'
import PageHeader from '../../components/PageHeader.tsx'
import { t } from '../../i18n/index.ts'
import { paths } from '../../paths.ts'
import { reachedApply } from '../flow.ts'
import { ErrorBlock, LoadingBlock } from '../Loading.tsx'
import '../page.css'

// 사이드바 "배포" — 가장 최근 배포의 현재 단계(W-05 ~ W-08)로 보내요 (A-03 목록 기준)
// 생성 단계에서 한 환경만 실패하고 나머지가 진행 중이면 W-05b예요 → 환경이 apply까지 갔는지로 판단해요
function stageOf(projectId: string, d: Deployment) {
  if (d.state === 'awaiting_approval') return paths.approve(projectId, d.id)
  if (d.state === 'queued' || (d.state === 'running' && !(d.targets ?? []).some(reachedApply))) return paths.generate(projectId, d.id)
  if (d.state === 'running') return paths.progress(projectId, d.id)
  return paths.result(projectId, d.id)
}

function CurrentDeployment() {
  const { projectId = '' } = useParams()
  const runs = useResource(() => api.listDeployments(projectId), [projectId])
  if (runs.error) return <ErrorBlock error={runs.error} />
  if (!runs.data) return <LoadingBlock />
  const latest = runs.data.items[0]
  if (!latest) {
    return (
      <div className="page">
        <PageHeader overline="Deploy" mock={isMocked('listDeployments')} title={t('배포')} />
        <EmptyState icon="play" title={t('아직 배포가 없어요')} description={t('사이드바의 새 배포로 시작해요')} />
      </div>
    )
  }
  return <Navigate to={stageOf(projectId, latest)} replace />
}

export default CurrentDeployment
