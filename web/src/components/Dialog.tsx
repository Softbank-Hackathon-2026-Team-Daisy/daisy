import { useEffect, useId, useRef, type ReactNode } from 'react'
import { t } from '../i18n/index.ts'
import Icon from './Icon.tsx'
import type { IconName } from './icons.ts'
import './Dialog.css'

// Figma 「06 · Dialog」. 네이티브 <dialog>라 포커스 가두기 · Esc 닫기가 기본으로 돼요
type DialogProps = {
  open: boolean
  onClose: () => void
  title: string
  icon?: IconName
  description?: ReactNode
  children?: ReactNode
  actions?: ReactNode
}

function Dialog({ open, onClose, title, icon, description, children, actions }: DialogProps) {
  const ref = useRef<HTMLDialogElement>(null)
  const titleId = useId()

  useEffect(() => {
    const dialog = ref.current
    if (!dialog) return
    if (open && !dialog.open) dialog.showModal()
    if (!open && dialog.open) dialog.close()
  }, [open])

  return (
    <dialog ref={ref} className="dialog" aria-labelledby={titleId} onClose={onClose}>
      <div className="dialog__header">
        {icon && <Icon name={icon} />}
        <h2 className="dialog__title t-h2" id={titleId}>
          {title}
        </h2>
        <button type="button" className="dialog__close" aria-label={t('닫기')} onClick={onClose}>
          <Icon name="x" size={16} />
        </button>
      </div>
      {description && <div className="dialog__desc">{description}</div>}
      {children}
      {actions && <div className="dialog__footer">{actions}</div>}
    </dialog>
  )
}

export default Dialog
