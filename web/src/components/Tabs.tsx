import type { KeyboardEvent } from 'react'
import CloudLogo from './CloudLogo.tsx'
import type { EnvType } from './env.ts'
import type { StatusTone } from './StatusBadge.tsx'
import './Tabs.css'

// Figma 「03 · Tab Item」 · 「05 · Tabs」. 환경별 plan · 스크립트 · 로그를 나눠 볼 때 써요. 탭 패널은 쓰는 쪽이 그려요
// env가 있으면 클라우드는 로고, 온프레미스는 색 점 (Env Tag와 같은 규칙). count · tone은 선택 — 줄 수와 상태 점
export type TabItem = { id: string; label: string; env?: EnvType; count?: number; tone?: StatusTone; toneLabel?: string }

type TabsProps = {
  items: TabItem[]
  value: string
  onChange: (id: string) => void
  label: string
  idPrefix?: string
}

function Tabs({ items, value, onChange, label, idPrefix = 'tab' }: TabsProps) {
  const onKeyDown = (e: KeyboardEvent, index: number) => {
    const step = e.key === 'ArrowRight' ? 1 : e.key === 'ArrowLeft' ? -1 : 0
    if (!step) return
    e.preventDefault()
    const next = items[(index + step + items.length) % items.length]
    onChange(next.id)
    document.getElementById(`${idPrefix}-${next.id}`)?.focus()
  }

  return (
    <div className="tabs" role="tablist" aria-label={label}>
      {items.map((item, i) => {
        const selected = item.id === value
        return (
          <button
            key={item.id}
            id={`${idPrefix}-${item.id}`}
            type="button"
            role="tab"
            aria-selected={selected}
            aria-controls={`${idPrefix}-panel-${item.id}`}
            tabIndex={selected ? 0 : -1}
            className="tabs__item"
            onClick={() => onChange(item.id)}
            onKeyDown={(e) => onKeyDown(e, i)}
          >
            {item.env &&
              (item.env === 'onprem' ? <span className="tabs__env" style={{ background: `var(--color-env-${item.env})` }} aria-hidden="true" /> : <CloudLogo env={item.env} />)}
            {item.label}
            {item.count != null && <span className="tabs__count">{item.count}</span>}
            {item.tone && <span className={`tabs__dot tabs__dot--${item.tone}`} role="img" aria-label={item.toneLabel} aria-hidden={item.toneLabel ? undefined : true} />}
          </button>
        )
      })}
    </div>
  )
}

export default Tabs
