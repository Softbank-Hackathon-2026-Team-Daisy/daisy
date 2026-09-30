import { useCallback, useEffect, useRef, useState } from 'react'

// 데이터를 불러오는 공통 훅. pollMs를 주면 서버 SSE 전까지 그 간격으로 다시 불러와요 (D2 5초 폴링)
export function useResource<T>(load: (signal: AbortSignal) => Promise<T>, deps: unknown[], pollMs?: number) {
  const [data, setData] = useState<T | null>(null)
  const [error, setError] = useState<Error | null>(null)
  const [loading, setLoading] = useState(true)
  const loadRef = useRef(load)
  loadRef.current = load

  const run = useCallback((signal: AbortSignal) => {
    return loadRef
      .current(signal)
      .then((d) => {
        if (!signal.aborted) {
          setData(d)
          setError(null)
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
    const timer = pollMs ? setInterval(() => void run(controller.signal), pollMs) : undefined
    return () => {
      controller.abort()
      if (timer) clearInterval(timer)
    }
    // deps는 쓰는 쪽이 넘겨요
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [...deps, tick, pollMs, run])

  return { data, error, loading, reload }
}
