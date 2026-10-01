import Icon from './Icon.tsx'
import Spinner from './Spinner.tsx'
import './StepItem.css'

// Figma 「05 · Step Item」. 파이프라인 · 검증 · apply 단계 한 줄 (대기 · 진행 · 완료 · 실패)
export type StepItemState = 'pending' | 'running' | 'done' | 'failed'

type StepItemProps = {
  state: StepItemState
  label: string
  duration?: string
}

function StepItem({ state, label, duration }: StepItemProps) {
  return (
    <div className={`step-item step-item--${state}`}>
      <span className="step-item__icon">
        {state === 'pending' && <Icon name="clock" size={16} />}
        {state === 'running' && <Spinner label={`${label} 진행 중`} />}
        {state === 'done' && <Icon name="circle-check" size={16} label="완료" />}
        {state === 'failed' && <Icon name="circle-x" size={16} label="실패" />}
      </span>
      <span className="step-item__label">{label}</span>
      <span className="t-mono-sm t-muted">{duration ?? '—'}</span>
    </div>
  )
}

export default StepItem
