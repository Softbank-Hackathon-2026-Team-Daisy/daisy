import { useEffect, useState } from 'react'
import InfraBlock from '../../components/InfraBlock.tsx'
import { CAPTION_MS, CAPTIONS, FIRST_CAPTION, type TransitionKind } from './captions.ts'
import './TransitionLoader.css'

// L-01 ~ L-03 전환 로딩 (Figma 「07 · Transition Loader」). 규칙은 AGENTS.md §5-6
// Stack 0 → 1 → 2 → 3 (블록마다 450ms) → 600ms 머묾 → 200ms 페이드아웃 → 0 반복
const DROP_MS = 450
const HOLD_MS = 600
const FADE_MS = 200

function useReducedMotion() {
  const [reduced, setReduced] = useState(() => window.matchMedia('(prefers-reduced-motion: reduce)').matches)
  useEffect(() => {
    const mq = window.matchMedia('(prefers-reduced-motion: reduce)')
    const onChange = () => setReduced(mq.matches)
    mq.addEventListener('change', onChange)
    return () => mq.removeEventListener('change', onChange)
  }, [])
  return reduced
}

function useStackCycle(enabled: boolean) {
  const [stack, setStack] = useState<0 | 1 | 2 | 3>(0)
  const [fading, setFading] = useState(false)
  useEffect(() => {
    if (!enabled) return
    const timers: number[] = []
    const cycle = () => {
      setFading(false)
      setStack(0)
      ;([1, 2, 3] as const).forEach((n, i) => timers.push(window.setTimeout(() => setStack(n), i * DROP_MS)))
      const fadeAt = 2 * DROP_MS + DROP_MS + HOLD_MS
      timers.push(window.setTimeout(() => setFading(true), fadeAt))
      timers.push(window.setTimeout(cycle, fadeAt + FADE_MS))
    }
    cycle()
    return () => timers.forEach(clearTimeout)
  }, [enabled])
  // 모션 줄이기면 떨어지는 모션 없이 Stack 3에 고정
  return enabled ? { stack, fading } : { stack: 3 as const, fading: false }
}

function useCaption(kind: TransitionKind) {
  const [index, setIndex] = useState(-1) // -1 = 화면별 첫 고정 문구
  useEffect(() => {
    const timer = window.setInterval(() => setIndex((i) => (i + 1) % CAPTIONS.length), CAPTION_MS)
    return () => clearInterval(timer)
  }, [])
  return index < 0 ? FIRST_CAPTION[kind] : CAPTIONS[index]
}

type TransitionLoaderProps = {
  kind: TransitionKind
  meta: string // 예: "STEP 1 · REPO", "STEP 4 · 3 ENVS"
}

function TransitionLoader({ kind, meta }: TransitionLoaderProps) {
  const reduced = useReducedMotion()
  const { stack, fading } = useStackCycle(!reduced)
  const caption = useCaption(kind)

  return (
    <div className="transition-loader">
      <InfraBlock stack={stack} animated={!reduced} fading={fading} />
      <div className="transition-loader__text">
        {/* 단계 변화만 스크린리더에 알려요. 돌아가는 문구는 읽지 않아요 (aria-live 끔) */}
        <h2 className="t-h2" role="status">
          잠시만 기다려주세요
        </h2>
        <p className="transition-loader__caption t-body-sm t-muted" aria-hidden="true" key={caption}>
          {caption}
        </p>
        <p className="t-overline t-muted">{meta}</p>
      </div>
    </div>
  )
}

export default TransitionLoader
