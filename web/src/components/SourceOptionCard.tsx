import Icon from './Icon.tsx'
import type { IconName } from './icons.ts'
import './SourceOptionCard.css'

// Figma 「04 · Source Option Card」. 앱 입력 방식 카드 — 지금은 GitHub 하나 (업로드 W-02b는 범위 제외)
type SourceOptionCardProps = {
  icon: IconName
  title: string
  description: string
  selected: boolean
  onSelect?: () => void
}

function SourceOptionCard({ icon, title, description, selected, onSelect }: SourceOptionCardProps) {
  return (
    <button type="button" className="source-card" aria-pressed={selected} onClick={onSelect}>
      <span className="source-card__icon">
        <Icon name={icon} />
      </span>
      <span className="t-h2">{title}</span>
      <span className="t-muted">{description}</span>
    </button>
  )
}

export default SourceOptionCard
