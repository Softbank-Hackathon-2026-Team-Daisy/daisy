import type { ButtonHTMLAttributes, ReactNode } from 'react'
import './Button.css'

// Figma 「02 Core · Button」. 노란색(primary)은 배포 버튼에만 써요 (AGENTS.md §5-1)
export type ButtonVariant = 'primary' | 'secondary' | 'outline' | 'ghost' | 'destructive'

type ButtonProps = ButtonHTMLAttributes<HTMLButtonElement> & {
  variant?: ButtonVariant
  // lg: W-06 "승인하고 배포" 48px 버튼 전용
  size?: 'md' | 'lg'
  leading?: ReactNode
  trailing?: ReactNode
}

function Button({
  variant = 'secondary',
  size = 'md',
  leading,
  trailing,
  className,
  type = 'button',
  children,
  ...rest
}: ButtonProps) {
  const classes = ['btn', `btn--${variant}`, size === 'lg' && 'btn--lg', className].filter(Boolean).join(' ')
  return (
    <button type={type} className={classes} {...rest}>
      {leading}
      {children}
      {trailing}
    </button>
  )
}

export default Button
