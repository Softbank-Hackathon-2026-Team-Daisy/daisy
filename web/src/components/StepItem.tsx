import Icon from './Icon.tsx'
import Spinner from './Spinner.tsx'
import './StepItem.css'

// Figma 「05 · Step Item」. 파이프라인 · 검증 · apply 단계 한 줄 (대기 · 진행 · 완료 · 실패 · 건너뜀)
// skipped는 웹 전용 상태예요 — Jenkins가 실행하지 않은 단계(NOT_EXECUTED, 예: daisy-ci의 Trigger CD)
export type StepItemState = 'pending' | 'running' | 'done' | 'failed' | 'skipped'

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
        {state === 'skipped' && <Icon name="minus" size={16} label="건너뜀" />}
      </span>
      <span className="step-item__label">{label}</span>
      <span className="t-mono-sm t-muted">{state === 'skipped' ? '건너뜀' : (duration ?? '—')}</span>
    </div>
  )
}

export default StepItem
