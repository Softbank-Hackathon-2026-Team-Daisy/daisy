import { API_BASE_URL, getAccessToken, notifyUnauthorized } from './client.ts'

// SSE — EventSource는 Authorization 헤더를 못 붙여서 fetch 스트림을 직접 읽어요 (WR-01, SPEC.md §6-2)
// 서버 형식: id(= seq) / event / data(한 줄 JSON), 빈 줄로 끊어요. 재연결은 Last-Event-ID 헤더
// heartbeat는 15초마다(연결 직후 한 번 바로) — 두 번 연속 못 받으면 끊긴 걸로 보고 다시 붙어요

const HEARTBEAT_MS = 15_000
const STALE_MS = HEARTBEAT_MS * 2

export type ServerEvent = { id: number | null; event: string; data: unknown }
export type RealtimeState = 'connected' | 'reconnecting' | 'disconnected'

// SSE 텍스트 조각을 이벤트로 바꿔요. 남은 조각은 rest로 돌려줘요
export function parseSse(buffer: string): { events: ServerEvent[]; rest: string } {
  const events: ServerEvent[] = []
  const blocks = buffer.split(/\r?\n\r?\n/)
  const rest = blocks.pop() ?? ''
  for (const block of blocks) {
    let id: number | null = null
    let event = 'message'
    const data: string[] = []
    for (const line of block.split(/\r?\n/)) {
      if (line.startsWith(':')) continue
      const i = line.indexOf(':')
      const field = i === -1 ? line : line.slice(0, i)
      const value = i === -1 ? '' : line.slice(i + 1).replace(/^ /, '')
      if (field === 'id') id = Number(value)
      else if (field === 'event') event = value
      else if (field === 'data') data.push(value)
    }
    if (data.length === 0) continue
    const text = data.join('\n')
    let parsed: unknown = text
    try {
      parsed = JSON.parse(text)
    } catch {
      // JSON이 아니면 문자열 그대로 넘겨요
    }
    events.push({ id, event, data: parsed })
  }
  return { events, rest }
}

type SubscribeOptions = {
  // 첫 연결의 Last-Event-ID — 이 seq 다음부터 받아요 (프로젝트 채널은 A-12 last_seq). 없으면 처음부터
  since?: number | null
  onEvent: (e: ServerEvent) => void
  onState: (s: RealtimeState) => void
  // 서버가 resync를 보내면(놓친 이벤트를 못 채울 때) 스냅샷(A-04)을 다시 불러요
  onResync: () => void
}

class Unauthorized extends Error {}
class TooMany extends Error {}

// 계정당 SSE 연결 상한(서버 4개)에 걸리면 이만큼 쉬었다가 다시 붙어요. 그동안 화면은 5초 폴링으로 버텨요
const TOO_MANY_WAIT_MS = 60_000

// 채널에 붙고, 끊기면 Last-Event-ID로 다시 붙어요. 3번 연속 실패하면 disconnected → 쓰는 쪽이 폴링으로 버텨요
// 401이면 다시 붙지 않고 세션 만료로 보내요
export function subscribe(path: string, { since = null, onEvent, onState, onResync }: SubscribeOptions): () => void {
  const controller = new AbortController()
  let lastId: number | null = since
  let failures = 0

  const connect = async () => {
    while (!controller.signal.aborted) {
      // 이번 연결만 끊는 컨트롤러 — heartbeat가 끊기면 이것만 abort하고 다시 붙어요
      const attempt = new AbortController()
      const stop = () => attempt.abort()
      controller.signal.addEventListener('abort', stop)
      let watchdog: ReturnType<typeof setTimeout> | undefined
      const alive = () => {
        clearTimeout(watchdog)
        watchdog = setTimeout(() => attempt.abort(), STALE_MS)
      }
      try {
        const headers: Record<string, string> = { Accept: 'text/event-stream' }
        const token = getAccessToken()
        if (token) headers.Authorization = `Bearer ${token}`
        if (lastId !== null) headers['Last-Event-ID'] = String(lastId)
        alive()
        const res = await fetch(`${API_BASE_URL}${path}`, { headers, signal: attempt.signal })
        if (res.status === 401) throw new Unauthorized()
        if (res.status === 429) throw new TooMany()
        if (!res.ok || !res.body) throw new Error(`SSE ${res.status}`)
        failures = 0
        onState('connected')
        const reader = res.body.pipeThrough(new TextDecoderStream()).getReader()
        let buffer = ''
        for (;;) {
          const { value, done } = await reader.read()
          if (done) break
          alive() // heartbeat(: 주석 줄)도 여기서 살아 있다고 봐요
          const parsed = parseSse(buffer + value)
          buffer = parsed.rest
          for (const e of parsed.events) {
            if (e.event === 'resync') {
              // 보관 범위 밖이라는 뜻이라 처음(0)부터 다시 받으면 또 resync가 올 수 있어요.
              // 서버가 알려 준 last_seq부터 이어 붙고, 화면은 스냅샷을 다시 읽어요
              const last = (e.data as { last_seq?: number } | null)?.last_seq
              lastId = typeof last === 'number' ? last : null
              onResync()
              continue
            }
            if (e.id !== null) lastId = e.id
            onEvent(e)
          }
        }
      } catch (e) {
        if (controller.signal.aborted) return
        if (e instanceof Unauthorized) {
          onState('disconnected')
          notifyUnauthorized(path)
          return
        }
        if (e instanceof TooMany) {
          onState('disconnected')
          await new Promise((r) => setTimeout(r, TOO_MANY_WAIT_MS))
          continue
        }
      } finally {
        clearTimeout(watchdog)
        controller.signal.removeEventListener('abort', stop)
      }
      failures += 1
      onState(failures >= 3 ? 'disconnected' : 'reconnecting')
      await new Promise((r) => setTimeout(r, Math.min(1000 * 2 ** failures, 10000)))
    }
  }

  void connect()
  return () => controller.abort()
}
