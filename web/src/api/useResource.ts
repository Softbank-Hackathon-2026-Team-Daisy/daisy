import { useCallback, useEffect, useRef, useState } from 'react'

// 서버 SSE 전 폴링 간격 (합의 5초)
export const POLL_MS = 5000
// SSE가 붙어 있을 때 놓친 이벤트를 메우는 안전망 간격
export const POLL_MS_LIVE = 30_000

// 데이터를 불러오는 공통 훅. pollMs를 주면 서버 SSE 전까지 그 간격으로 다시 불러와요 (D2 5초 폴링)
// done(data)가 true면 폴링을 멈춰요 — 끝난 배포 · 빌드는 더 부르지 않아요
export function useResource<T>(load: (signal: AbortSignal) => Promise<T>, deps: unknown[], pollMs?: number, done?: (data: T) => boolean) {
  const [data, setData] = useState<T | null>(null)
  const [error, setError] = useState<Error | null>(null)
  const [loading, setLoading] = useState(true)
  const loadRef = useRef(load)
  loadRef.current = load
  const doneRef = useRef(done)
  doneRef.current = done
  const timerRef = useRef<ReturnType<typeof setInterval> | undefined>(undefined)

  const run = useCallback((signal: AbortSignal) => {
    return loadRef
      .current(signal)
      .then((d) => {
        if (!signal.aborted) {
          setData(d)
          setError(null)
          if (doneRef.current?.(d)) clearInterval(timerRef.current)
        }
      })
      .catch((e: Error) => {
        if (!signal.aborted) setError(e)
      })
      .finally(() => {
        if (!signal.aborted) setLoading(false)
      })
  }, [])

  const [tick, setTick] = useState(0)
  const reload = useCallback(() => setTick((t) => t + 1), [])

  useEffect(() => {
    const controller = new AbortController()
    setLoading(true)
    void run(controller.signal)
    timerRef.current = pollMs ? setInterval(() => void run(controller.signal), pollMs) : undefined
    return () => {
      controller.abort()
      clearInterval(timerRef.current)
    }
    // deps는 쓰는 쪽이 넘겨요
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [...deps, tick, pollMs, run])

  return { data, error, loading, reload }
}
