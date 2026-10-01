import type { ReactNode } from 'react'
import Icon from './Icon.tsx'
import type { IconName } from './icons.ts'
import './Alert.css'

// Figma 「03 · Alert」. 화면 안에 고정으로 두는 안내 (잠깐 떴다 사라지는 건 Toast)
export type AlertType = 'info' | 'warning' | 'danger' | 'success'

const ICON: Record<AlertType, IconName> = {
  info: 'info',
  warning: 'alert-triangle',
  danger: 'circle-x',
  success: 'circle-check',
}

type AlertProps = {
  type: AlertType
  title: string
  children?: ReactNode
}

function Alert({ type, title, children }: AlertProps) {
  return (
    <div className={`alert alert--${type}`} role={type === 'danger' ? 'alert' : 'status'}>
      <span className="alert__icon">
        <Icon name={ICON[type]} />
      </span>
      <div className="alert__content">
        <p className="alert__title">{title}</p>
        {children && <div className="alert__desc">{children}</div>}
      </div>
    </div>
  )
}

export default Alert
