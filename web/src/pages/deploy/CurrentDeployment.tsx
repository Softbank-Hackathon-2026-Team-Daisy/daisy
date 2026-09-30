import { Navigate, useParams } from 'react-router'
import { api } from '../../api/endpoints.ts'
import type { Deployment } from '../../api/types.ts'
import { useResource } from '../../api/useResource.ts'
import EmptyState from '../../components/EmptyState.tsx'
import PageHeader from '../../components/PageHeader.tsx'
import { paths } from '../../paths.ts'
import { ErrorBlock, LoadingBlock } from '../Loading.tsx'
import '../page.css'

// 사이드바 "배포" — 가장 최근 배포의 현재 단계(W-05 ~ W-08)로 보내요 (A-03 목록 기준)
const APPLYING = new Set(['applying', 'verifying', 'succeeded', 'failed'])

function stageOf(projectId: string, d: Deployment) {
  if (d.state === 'awaiting_approval') return paths.approve(projectId, d.id)
  if (d.state === 'queued' || (d.state === 'running' && !d.targets.some((t) => APPLYING.has(t.state)))) return paths.generate(projectId, d.id)
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
        <PageHeader overline="Deploy" title="배포" />
        <EmptyState icon="play" title="아직 배포가 없어요" description="사이드바의 새 배포로 시작해요" />
      </div>
    )
  }
  return <Navigate to={stageOf(projectId, latest)} replace />
}

export default CurrentDeployment
