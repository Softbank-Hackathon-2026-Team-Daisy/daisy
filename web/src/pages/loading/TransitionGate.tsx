import { useState, type ReactNode } from 'react'
import { useLocation } from 'react-router'
import Stepper from '../../components/Stepper.tsx'
import type { TransitionKind } from './captions.ts'
import TransitionLoader from './TransitionLoader.tsx'

// 화면 사이 전환 로딩. 앞 화면에서 { transition } 상태로 넘어왔고 아직 준비가 안 됐을 때만 로딩을 보여줘요
// 준비되면(서버 완료 이벤트 또는 스냅샷) 바로 화면으로 넘어가고, 다시 로딩으로 돌아가지 않아요
// L-01 W-02 → W-03 (빌드가 나타날 때까지) · L-02 W-04 → W-05 (생성이 시작될 때까지) · L-03 W-06 → W-07 (apply가 시작될 때까지)

const STEP: Record<TransitionKind, 1 | 3 | 5> = { l01: 1, l02: 3, l03: 5 }

type TransitionGateProps = {
  kind: TransitionKind
  ready: boolean
  meta: string
  children: ReactNode
}

function TransitionGate({ kind, ready, meta, children }: TransitionGateProps) {
  const location = useLocation()
  const entered = (location.state as { transition?: TransitionKind } | null)?.transition === kind
  const [released, setReleased] = useState(!entered)
  // 한 번 준비되면 다시 로딩으로 돌아가지 않아요 (렌더 중에 한 번만 고정)
  if (ready && !released) setReleased(true)

  if (released || ready) return <>{children}</>
  return (
    <div className="page">
      <Stepper current={STEP[kind]} />
      <TransitionLoader kind={kind} meta={meta} />
    </div>
  )
}

export default TransitionGate
