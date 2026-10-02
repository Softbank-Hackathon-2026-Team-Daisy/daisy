import { useEffect, useState, type ReactNode } from 'react'
import { useLocation } from 'react-router'
import Stepper from '../../components/Stepper.tsx'
import type { TransitionKind } from './captions.ts'
import TransitionLoader from './TransitionLoader.tsx'

// 화면 사이 전환 로딩. 앞 화면에서 { transition } 상태로 넘어왔고 아직 준비가 안 됐을 때만 로딩을 보여줘요
// 준비되면(서버 완료 이벤트 또는 스냅샷) 바로 화면으로 넘어가고, 다시 로딩으로 돌아가지 않아요
// L-01 W-02 → W-03 (빌드가 나타날 때까지) · L-02 W-04 → W-05 (생성이 시작될 때까지) · L-03 W-06 → W-07 (apply가 시작될 때까지)

// Stepper는 로딩이 끝나면 보일 화면의 단계를 가리켜요 (로딩 문구의 "Step n"과 같게). L-01은 문구가 "Step 1 · Repo"라 1이에요
const STEP: Record<TransitionKind, 1 | 4 | 5> = { l01: 1, l02: 4, l03: 5 }

// 실서버에서 Jenkins 결과가 안 오면(빌드 · 생성 시작 신호 없음) 로딩에 갇히지 않게, 이 시간이 지나면 화면을 보여줘요
// 화면은 자기 빈 상태("아직 빌드가 없어요" · 대기 중)를 보여주고 SSE · 폴링으로 계속 갱신해요
const MAX_WAIT_MS = 20_000

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
  useEffect(() => {
    if (released) return
    const timer = setTimeout(() => setReleased(true), MAX_WAIT_MS)
    return () => clearTimeout(timer)
  }, [released])

  if (released || ready) return <>{children}</>
  return (
    <div className="page">
      <Stepper current={STEP[kind]} />
      <TransitionLoader kind={kind} meta={meta} />
    </div>
  )
}

export default TransitionGate
