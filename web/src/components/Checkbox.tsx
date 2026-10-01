import type { InputHTMLAttributes, ReactNode } from 'react'
import './Checkbox.css'

// Figma 「02 Core · Checkbox」. 실제 <input type="checkbox">를 숨기고 18px 박스를 그려요 (키보드 · 스크린리더 그대로)
type CheckboxProps = Omit<InputHTMLAttributes<HTMLInputElement>, 'type'> & {
  children?: ReactNode
}

function Checkbox({ children, className, ...rest }: CheckboxProps) {
  return (
    <label className={['checkbox', className].filter(Boolean).join(' ')}>
      <input type="checkbox" className="checkbox__input" {...rest} />
      <span className="checkbox__box" aria-hidden="true">
        <svg viewBox="0 0 18 18" width="18" height="18">
          <path d="M4 9.5L7.5 13L14 5.5" fill="none" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" />
        </svg>
      </span>
      {children}
    </label>
  )
}

export default Checkbox
