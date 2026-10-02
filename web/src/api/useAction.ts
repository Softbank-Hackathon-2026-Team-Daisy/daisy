import { useRef, useState } from 'react'
import { ApiError, errorMessage, newIdempotencyKey } from './client.ts'

// 응답을 못 받은 실패 — 서버가 처리했는지 모르는 경우예요 (네트워크 오류 · 5xx · 그 밖의 예외)
const unanswered = (e: unknown) => !(e instanceof ApiError) || e.status === 0 || e.status >= 500

// 버튼 한 번 = 요청 하나. 누르는 동안 pending이라 버튼을 끄고, 두 번 눌러도 한 번만 보내요
// Idempotency-Key는 동작마다 하나 만들어서 넘겨요 (서버가 같은 키를 다시 받으면 같은 결과를 돌려줘요)
// request(요청 내용)를 주면, 응답을 못 받고 실패한 뒤 같은 내용으로 다시 누를 때 같은 키를 다시 보내요.
// 서버가 첫 요청을 처리했는데 응답만 사라졌어도 배포가 두 개 생기지 않게요 (#86). 성공 · 4xx · 내용이 바뀌면 새 키예요
export function useAction() {
  const busy = useRef(false)
  const last = useRef<{ request: string; key: string } | null>(null)
  const [pending, setPending] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const run = async <T>(fn: (key: string) => Promise<T>, fallback: string, request?: unknown): Promise<T | undefined> => {
    if (busy.current) return undefined
    busy.current = true
    setPending(true)
    setError(null)
    const sig = request === undefined ? null : JSON.stringify(request)
    const key = sig !== null && last.current?.request === sig ? last.current.key : newIdempotencyKey()
    try {
      const result = await fn(key)
      last.current = null
      return result
    } catch (e) {
      last.current = sig !== null && unanswered(e) ? { request: sig, key } : null
      setError(errorMessage(e, fallback))
      return undefined
    } finally {
      busy.current = false
      setPending(false)
    }
  }

  return { run, pending, error, setError }
}
