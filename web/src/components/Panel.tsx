import type { ReactNode } from 'react'
import MockBadge from './MockBadge.tsx'
import './Panel.css'

// 화면 안의 카드 영역 (card 배경 · 1px line · radius 4 · 24px 여백). 와이어프레임의 "환경별 현재 버전", "지금 할 일" 같은 칸
type PanelProps = {
  title?: ReactNode
  aside?: ReactNode
  children: ReactNode
  className?: string
  // 이 칸만 목업 데이터를 보여줄 때 제목 옆에 MOCK 배지 (루트 AGENTS.md §4-6)
  mock?: boolean
}

function Panel({ title, aside, children, className, mock = false }: PanelProps) {
  return (
    <section className={['panel', className].filter(Boolean).join(' ')}>
      {(title || aside || mock) && (
        <header className="panel__header">
          {(title || mock) && (
            <h2 className="t-h2" style={{ display: 'flex', alignItems: 'center', gap: 'var(--space-2)' }}>
              {title}
              {mock && <MockBadge />}
            </h2>
          )}
          {aside}
        </header>
      )}
      {children}
    </section>
  )
}

export default Panel
