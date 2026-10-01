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
  onEvent: (e: ServerEvent) => void
  onState: (s: RealtimeState) => void
  // 서버가 resync를 보내면(놓친 이벤트를 못 채울 때) 스냅샷(A-04)을 다시 불러요
  onResync: () => void
}

class Unauthorized extends Error {}

// 채널에 붙고, 끊기면 Last-Event-ID로 다시 붙어요. 3번 연속 실패하면 disconnected → 쓰는 쪽이 폴링으로 버텨요
// 401이면 다시 붙지 않고 세션 만료로 보내요
export function subscribe(path: string, { onEvent, onState, onResync }: SubscribeOptions): () => void {
  const controller = new AbortController()
  let lastId: number | null = null
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
              lastId = null
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
