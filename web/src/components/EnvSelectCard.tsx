import Checkbox from './Checkbox.tsx'
import EnvTag from './EnvTag.tsx'
import type { EnvType } from './env.ts'
import './EnvSelectCard.css'

// Figma 「02 Core · Env Select Card」 — W-04 환경 선택. 카드 전체가 체크박스 라벨이에요
type EnvSelectCardProps = {
  env: EnvType
  title: string
  description?: string
  selected: boolean
  recommended?: boolean
  disabled?: boolean
  onChange: (selected: boolean) => void
}

function EnvSelectCard({ env, title, description, selected, recommended, disabled, onChange }: EnvSelectCardProps) {
  return (
    <Checkbox
      className={['env-card', selected && 'env-card--selected'].filter(Boolean).join(' ')}
      checked={selected}
      disabled={disabled}
      onChange={(e) => onChange(e.target.checked)}
    >
      <span className="env-card__header">
        <EnvTag env={env} />
        {recommended && <span className="env-card__recommend">추천</span>}
      </span>
      <span className="env-card__title">{title}</span>
      {description && <span className="env-card__desc t-body-sm t-muted">{description}</span>}
    </Checkbox>
  )
}

export default EnvSelectCard
