import type { ReactNode } from 'react'
import { t } from '../i18n/index.ts'
import Icon from './Icon.tsx'
import type { IconName } from './icons.ts'
import './Toast.css'

// Figma 「03 · Toast」. 잠깐 떴다 사라지는 알림 (띄우고 닫는 타이밍은 쓰는 쪽이 정해요)
export type ToastType = 'success' | 'error' | 'info'

const ICON: Record<ToastType, IconName> = {
  success: 'circle-check',
  error: 'circle-x',
  info: 'info',
}

type ToastProps = {
  type: ToastType
  title: string
  children?: ReactNode
  onClose?: () => void
}

function Toast({ type, title, children, onClose }: ToastProps) {
  return (
    <div className={`toast toast--${type}`} role={type === 'error' ? 'alert' : 'status'}>
      <span className="toast__icon">
        <Icon name={ICON[type]} />
      </span>
      <div className="toast__content">
        <p className="toast__title">{title}</p>
        {children && <div className="toast__desc">{children}</div>}
      </div>
      {onClose && (
        <button type="button" className="toast__close" aria-label={t('닫기')} onClick={onClose}>
          <Icon name="x" size={16} />
        </button>
      )}
    </div>
  )
}

export default Toast
