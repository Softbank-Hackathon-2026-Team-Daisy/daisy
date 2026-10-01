import { useRef, useState } from 'react'
import { errorMessage, newIdempotencyKey } from './client.ts'

// 버튼 한 번 = 요청 하나. 누르는 동안 pending이라 버튼을 끄고, 두 번 눌러도 한 번만 보내요
// Idempotency-Key는 동작마다 하나 만들어서 넘겨요 (서버가 같은 키를 다시 받으면 같은 결과를 돌려줘요)
export function useAction() {
  const busy = useRef(false)
  const [pending, setPending] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const run = async <T>(fn: (key: string) => Promise<T>, fallback: string): Promise<T | undefined> => {
    if (busy.current) return undefined
    busy.current = true
    setPending(true)
    setError(null)
    try {
      return await fn(newIdempotencyKey())
    } catch (e) {
      setError(errorMessage(e, fallback))
      return undefined
    } finally {
      busy.current = false
      setPending(false)
    }
  }

  return { run, pending, error, setError }
}
