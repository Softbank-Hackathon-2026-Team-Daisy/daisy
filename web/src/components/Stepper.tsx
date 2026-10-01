import { Fragment } from 'react'
import Icon from './Icon.tsx'
import './Stepper.css'

// Figma 「04 · Stepper · Step Indicator」. 배포 흐름 6단계 — 현재 단계만 노란색이에요
const FLOW_STEPS = ['저장소 연결', '이미지 빌드', '대상 환경', '생성 · 검증', '승인 · 배포', '결과'] as const

function Stepper({ current }: { current: 1 | 2 | 3 | 4 | 5 | 6 }) {
  return (
    <ol className="stepper" aria-label="배포 단계">
      {FLOW_STEPS.map((label, i) => {
        const n = i + 1
        const state = n < current ? 'done' : n === current ? 'current' : 'upcoming'
        return (
          <Fragment key={label}>
            {i > 0 && <li className={`stepper__connector ${n <= current ? 'stepper__connector--done' : ''}`} aria-hidden="true" />}
            <li className={`stepper__step stepper__step--${state}`} aria-current={state === 'current' ? 'step' : undefined}>
              <span className="stepper__bullet">{state === 'done' ? <Icon name="check" size={14} /> : n}</span>
              {label}
            </li>
          </Fragment>
        )
      })}
    </ol>
  )
}

export default Stepper
