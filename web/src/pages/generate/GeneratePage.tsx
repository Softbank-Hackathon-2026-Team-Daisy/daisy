import { useParams } from 'react-router'
import { api } from '../../api/endpoints.ts'
import { useResource } from '../../api/useResource.ts'
import TransitionGate from '../loading/TransitionGate.tsx'
import Placeholder from '../Placeholder.tsx'

// W-05 · W-05b 인프라 코드 생성 · 검증 (STEP 4). 본문은 Step E에서 채워요
function GeneratePage() {
  const { deploymentId = '' } = useParams()
  const deployment = useResource(() => api.getDeployment(deploymentId), [deploymentId], 2000)
  const d = deployment.data
  // L-02: 환경 선택에서 넘어왔으면 생성이 시작될 때까지(작업 큐 대기가 끝날 때까지) 전환 로딩
  const ready = !!d && d.state !== 'queued'

  return (
    <TransitionGate kind="l02" ready={ready} meta={`Step 4 · ${d?.targets.length ?? 0} envs`}>
      <Placeholder id="W-05 · W-05b · STEP 4" title="인프라 코드 생성 · 검증" />
    </TransitionGate>
  )
}

export default GeneratePage
