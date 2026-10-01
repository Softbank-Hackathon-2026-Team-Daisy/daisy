import Alert from '../components/Alert.tsx'
import Skeleton from '../components/Skeleton.tsx'

// 화면 데이터를 불러오는 중 · 실패했을 때 공통 표시
export function LoadingBlock() {
  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-3)' }} aria-busy="true">
      <Skeleton shape="line" width="40%" />
      <Skeleton shape="block" width="100%" height={160} />
      <Skeleton shape="block" width="100%" height={120} />
    </div>
  )
}

export function ErrorBlock({ error }: { error: Error }) {
  return (
    <Alert type="danger" title="불러오지 못했어요">
      {error.message}
    </Alert>
  )
}
