import type { KeyboardEvent } from 'react'
import type { EnvType } from './env.ts'
import './Tabs.css'

// Figma 「03 · Tab Item」 · 「05 · Tabs」. 환경별 plan · 스크립트를 나눠 볼 때 써요. 탭 패널은 쓰는 쪽이 그려요
export type TabItem = { id: string; label: string; env?: EnvType }

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
            {item.env && <span className="tabs__env" style={{ background: `var(--color-env-${item.env})` }} />}
            {item.label}
          </button>
        )
      })}
    </div>
  )
}

export default Tabs
