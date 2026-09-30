// 화면 표시용 포맷 — 시간은 서버가 ISO 8601 UTC로 줘요 (ios/SPEC.md R-05)

export function relativeTime(iso: string, now = Date.now()) {
  const diff = Math.max(0, now - new Date(iso).getTime())
  const min = Math.floor(diff / 60_000)
  if (min < 1) return '방금'
  if (min < 60) return `${min}분 전`
  const hour = Math.floor(min / 60)
  const d = new Date(iso)
  const today = new Date(now)
  if (d.toDateString() === today.toDateString()) return `${hour}시간 전`
  const yesterday = new Date(now - 86_400_000)
  if (d.toDateString() === yesterday.toDateString()) return '어제'
  return `${d.getMonth() + 1}/${d.getDate()}`
}

export function clockTime(iso: string) {
  const d = new Date(iso)
  return `${String(d.getHours()).padStart(2, '0')}:${String(d.getMinutes()).padStart(2, '0')}`
}

// 커밋 해시는 앞 7자리
export const shortCommit = (commit: string) => commit.slice(0, 7)

export const won = (n: number) => `₩${n.toLocaleString('ko-KR')}`

export const count = (n: number) => n.toLocaleString('ko-KR')

// 소요 시간 — "42s", "1m 03s". 진행 중이면 뒤에 "…"
export function duration(ms: number | undefined, running = false) {
  if (ms == null) return undefined
  const sec = Math.round(ms / 1000)
  const text = sec < 60 ? `${sec}s` : `${Math.floor(sec / 60)}m ${String(sec % 60).padStart(2, '0')}s`
  return running ? `${text}…` : text
}
