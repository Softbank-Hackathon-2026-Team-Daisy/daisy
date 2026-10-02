// 화면 표시용 포맷 — 시간은 서버가 ISO 8601 UTC로 줘요 (ios/SPEC.md R-05)
// 문구 · 숫자 표기는 화면 언어를 따라요 (#75)
import { locale, t } from '../i18n/index.ts'

export function relativeTime(iso: string, now = Date.now()) {
  const diff = Math.max(0, now - new Date(iso).getTime())
  const min = Math.floor(diff / 60_000)
  if (min < 1) return t('방금')
  if (min < 60) return t('{n}분 전', { n: min })
  const hour = Math.floor(min / 60)
  const d = new Date(iso)
  const today = new Date(now)
  if (d.toDateString() === today.toDateString()) return t('{n}시간 전', { n: hour })
  const yesterday = new Date(now - 86_400_000)
  if (d.toDateString() === yesterday.toDateString()) return t('어제')
  return `${d.getMonth() + 1}/${d.getDate()}` // 세 언어 모두 "9/30"
}

export function clockTime(iso: string) {
  const d = new Date(iso)
  return `${String(d.getHours()).padStart(2, '0')}:${String(d.getMinutes()).padStart(2, '0')}`
}

// 커밋 해시는 앞 7자리
export const shortCommit = (commit: string) => commit.slice(0, 7)

// 이미지 digest — "sha256:" + 64자리라 표에 다 넣으면 넘쳐요. 앞 10 · 뒤 4자리만 보여주고 전체는 title로 (동일성 검증 표)
// 환경이 4개면 칸이 좁아서 "sha256:" 접두어도 빼요 — 행 이름이 이미 "이미지 digest"예요
export function shortDigest(digest: string) {
  const hex = digest.includes(':') ? digest.slice(digest.indexOf(':') + 1) : digest
  return hex.length <= 16 ? hex : `${hex.slice(0, 10)}…${hex.slice(-4)}`
}

// 서버가 확인하지 못한 값은 null로 와요 (0으로 채우지 않아요, #13) → "—"
export const won = (n: number | null | undefined) => (n == null ? '—' : `₩${n.toLocaleString(locale())}`)

export const count = (n: number | null | undefined) => (n == null ? '—' : n.toLocaleString(locale()))

// 소요 시간 — "42s", "1m 03s". 진행 중이면 뒤에 "…"
export function duration(ms: number | undefined, running = false) {
  if (ms == null) return undefined
  const sec = Math.round(ms / 1000)
  const text = sec < 60 ? `${sec}s` : `${Math.floor(sec / 60)}m ${String(sec % 60).padStart(2, '0')}s`
  return running ? `${text}…` : text
}
