import type { ReactNode } from 'react'
import MockBadge from './MockBadge.tsx'

// 화면 제목 영역: 오버라인 · 제목 · 설명. 목업 데이터를 쓰는 동안 MOCK 배지를 붙여요 (루트 AGENTS.md §4-6)
// mock: 이 화면이 목업으로 답하는 API를 쓰는지 (isMocked(...)로 넘겨요). 기본은 false — 앱 어딘가의 목업 때문에 실데이터 화면에 배지가 붙지 않게 (#102).
// 화면 일부만 목업이면 그 Panel에 mock을 넘겨요
type PageHeaderProps = {
  overline: string
  title: ReactNode
  description?: ReactNode
  badge?: ReactNode
  mock?: boolean
}

function PageHeader({ overline, title, description, badge, mock = false }: PageHeaderProps) {
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
