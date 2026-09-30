import { useParams } from 'react-router'
import { api } from '../../api/endpoints.ts'
import { useResource } from '../../api/useResource.ts'
import TransitionGate from '../loading/TransitionGate.tsx'
import Placeholder from '../Placeholder.tsx'

// W-07 배포 중 (STEP 5). 본문은 Step E에서 채워요
const APPLY_STARTED = new Set(['applying', 'verifying', 'succeeded', 'failed'])

function ProgressPage() {
  const { deploymentId = '' } = useParams()
  const deployment = useResource(() => api.getDeployment(deploymentId), [deploymentId], 2000)
  const d = deployment.data
  // L-03: 승인에서 넘어왔으면 한 환경이라도 apply를 시작할 때까지 전환 로딩
  const ready = !!d && d.targets.some((t) => APPLY_STARTED.has(t.state))

  return (
    <TransitionGate kind="l03" ready={ready} meta={`Step 5 · ${d?.targets.length ?? 0} envs`}>
      <Placeholder id="W-07 · STEP 5" title="배포 중" />
    </TransitionGate>
  )
}

export default ProgressPage
