import type { ReactNode } from 'react'
import Icon from './Icon.tsx'
import type { IconName } from './icons.ts'
import './EmptyState.css'

// Figma 「06 · Empty State」. 목록이 비었을 때 다음 행동을 알려줘요
type EmptyStateProps = {
  icon: IconName
  title: string
  description?: string
  action?: ReactNode
}

function EmptyState({ icon, title, description, action }: EmptyStateProps) {
  return (
    <div className="empty-state">
      <span className="empty-state__icon">
        <Icon name={icon} />
      </span>
      <p className="t-label">{title}</p>
      {description && <p className="t-body-sm t-muted">{description}</p>}
      {action}
    </div>
  )
}

export default EmptyState
