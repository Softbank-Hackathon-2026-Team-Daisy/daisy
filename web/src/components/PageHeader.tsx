import type { ReactNode } from 'react'
import { USE_MOCK } from '../api/client.ts'
import MockBadge from './MockBadge.tsx'

// 화면 제목 영역: 오버라인 · 제목 · 설명. 목업 데이터를 쓰는 동안 MOCK 배지를 붙여요 (루트 AGENTS.md §4-6)
type PageHeaderProps = {
  overline: string
  title: ReactNode
  description?: ReactNode
  badge?: ReactNode
}

function PageHeader({ overline, title, description, badge }: PageHeaderProps) {
  return (
    <header style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-2)' }}>
      <p className="t-overline t-muted" style={{ display: 'flex', alignItems: 'center', gap: 'var(--space-2)' }}>
        {overline}
        {USE_MOCK && <MockBadge />}
      </p>
      <h1 className="t-h1" style={{ display: 'flex', alignItems: 'center', gap: 'var(--space-3)' }}>
        {title}
        {badge}
      </h1>
      {description && <p className="t-muted">{description}</p>}
    </header>
  )
}

export default PageHeader
