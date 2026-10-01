import type { InputHTMLAttributes } from 'react'
import './Input.css'

// Figma 「02 Core · Input」. Focus · Disabled는 브라우저 상태로, Error는 invalid로 표시해요
type InputProps = InputHTMLAttributes<HTMLInputElement> & {
  invalid?: boolean
}

function Input({ invalid = false, className, ...rest }: InputProps) {
  const classes = ['input', invalid && 'input--error', className].filter(Boolean).join(' ')
  return <input className={classes} aria-invalid={invalid || undefined} {...rest} />
}

export default Input
