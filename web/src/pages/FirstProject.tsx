import { Navigate } from 'react-router'
import { useProjects } from '../api/useWorkspace.ts'
import EmptyState from '../components/EmptyState.tsx'
import { t } from '../i18n/index.ts'
import { paths } from '../paths.ts'
import { ErrorBlock, LoadingBlock } from './Loading.tsx'

// 프로젝트를 정하지 않고 들어오면(로그인 직후 · 모르는 주소) 프로젝트 목록(A-01)의 첫 프로젝트로 보내요
function FirstProject() {
  const projects = useProjects()
  if (projects.error) return <ErrorBlock error={projects.error} />
  if (!projects.data) return <LoadingBlock />
  const first = projects.data.items[0]
  if (!first) {
    return <EmptyState icon="git-merge" title={t('연결된 프로젝트가 없어요')} description={t('저장소를 연결하면 여기서 시작해요')} />
  }
  return <Navigate to={paths.overview(first.id)} replace />
}

export default FirstProject
