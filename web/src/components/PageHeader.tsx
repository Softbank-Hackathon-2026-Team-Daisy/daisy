import type { ReactNode } from 'react'
import { SOME_MOCKED } from '../api/endpoints.ts'
import MockBadge from './MockBadge.tsx'

// 화면 제목 영역: 오버라인 · 제목 · 설명. 목업 데이터를 쓰는 동안 MOCK 배지를 붙여요 (루트 AGENTS.md §4-6)
// mock: 이 화면이 목업으로 답하는 API를 쓰는지 (isMocked). 안 넘기면 목업이 하나라도 있으면 붙여요 — 모르면 붙이는 쪽이 안전해요
type PageHeaderProps = {
  overline: string
  title: ReactNode
  description?: ReactNode
  badge?: ReactNode
  mock?: boolean
}

function PageHeader({ overline, title, description, badge, mock = SOME_MOCKED }: PageHeaderProps) {
  return (
    <header style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-2)' }}>
      <p className="t-overline t-muted" style={{ display: 'flex', alignItems: 'center', gap: 'var(--space-2)' }}>
        {overline}
        {mock && <MockBadge />}
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
