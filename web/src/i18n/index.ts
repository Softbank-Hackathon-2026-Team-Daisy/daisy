// 화면 언어 — 한국어 · English · 日本語, 기본값은 브라우저 언어 (#75, 앱 #73과 같은 방식)
// 한국어 원문이 곧 키예요: t('배포 시작') → 고른 언어의 번역, 번역이 없으면 원문 그대로
// 서버가 보내는 문장(error.message, plan 위험 설명 등)은 번역하지 않고 받은 그대로 보여줘요 (#74 안 A)
import { useSyncExternalStore } from 'react'
import { MESSAGES } from './messages.ts'

export type Lang = 'ko' | 'en' | 'ja'

export const LANGS: { value: Lang; label: string }[] = [
  { value: 'ko', label: '한국어' },
  { value: 'en', label: 'English' },
  { value: 'ja', label: '日本語' },
]

const STORAGE_KEY = 'unibloom.lang'

function browserLang(): Lang {
  for (const tag of navigator.languages ?? [navigator.language]) {
    const base = tag.toLowerCase().split('-')[0]
    if (base === 'ko' || base === 'en' || base === 'ja') return base
  }
  return 'ko'
}

// 'system'은 브라우저 언어를 따라요
export type LangSetting = Lang | 'system'

function savedSetting(): LangSetting {
  try {
    const v = localStorage.getItem(STORAGE_KEY)
    if (v === 'ko' || v === 'en' || v === 'ja') return v
  } catch {
    // 저장소를 못 쓰면 브라우저 언어로
  }
  return 'system'
}

let setting: LangSetting = savedSetting()
let lang: Lang = setting === 'system' ? browserLang() : setting
const listeners = new Set<() => void>()

document.documentElement.lang = lang

export const getLang = () => lang
export const getLangSetting = () => setting

export function setLangSetting(next: LangSetting) {
  setting = next
  try {
    if (next === 'system') localStorage.removeItem(STORAGE_KEY)
    else localStorage.setItem(STORAGE_KEY, next)
  } catch {
    // 이번 세션에만 적용돼요
  }
  const resolved = next === 'system' ? browserLang() : next
  if (resolved === lang) return
  lang = resolved
  document.documentElement.lang = lang
  listeners.forEach((l) => l())
}

function subscribe(listener: () => void) {
  listeners.add(listener)
  return () => listeners.delete(listener)
}

/** 언어가 바뀌면 다시 그려요 — 앱 최상단에서 한 번 써요 (main.tsx) */
export const useLang = () => useSyncExternalStore(subscribe, getLang)

/** 시간 · 숫자 표기용 로케일 */
export const locale = () => ({ ko: 'ko-KR', en: 'en-US', ja: 'ja-JP' })[lang]

type Vars = Record<string, string | number>

/** 번역 — {name} 자리는 vars로 채워요. t('{name} 로그', { name }) */
export function t(ko: string, vars?: Vars): string {
  const text = lang === 'ko' ? ko : (MESSAGES[ko]?.[lang] ?? missing(ko))
  return vars ? text.replace(/\{(\w+)\}/g, (m, k: string) => (k in vars ? String(vars[k]) : m)) : text
}

const warned = new Set<string>()
function missing(ko: string) {
  // 'AWS'처럼 한국어가 없는 이름은 번역할 게 없어요
  if (import.meta.env.DEV && /[가-힣]/.test(ko) && !warned.has(ko)) {
    warned.add(ko)
    console.warn(`[i18n] 번역 없음 (${lang}): ${ko}`)
  }
  return ko
}
