import type { ReactNode } from 'react'
import './Panel.css'

// 화면 안의 카드 영역 (card 배경 · 1px line · radius 4 · 24px 여백). 와이어프레임의 "환경별 현재 버전", "지금 할 일" 같은 칸
type PanelProps = {
  title?: ReactNode
  aside?: ReactNode
  children: ReactNode
  className?: string
}

function Panel({ title, aside, children, className }: PanelProps) {
  return (
    <section className={['panel', className].filter(Boolean).join(' ')}>
      {(title || aside) && (
        <header className="panel__header">
          {title && <h2 className="t-h2">{title}</h2>}
          {aside}
        </header>
      )}
      {children}
    </section>
  )
}

export default Panel
