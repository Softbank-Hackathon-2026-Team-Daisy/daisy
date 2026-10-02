import type { ReactNode } from 'react'
import Button from './Button.tsx'
import { t } from '../i18n/index.ts'

// Figma 「05 · Approval Bar」. W-06 맨 아래 — 노란 48px "승인하고 배포"가 화면에서 가장 큰 요소예요
type ApprovalBarProps = {
  title: string
  meta: ReactNode
  onApprove: () => void
  onReject: () => void
  disabled?: boolean
  pending?: boolean
  note?: ReactNode
}

function ApprovalBar({ title, meta, onApprove, onReject, disabled, pending, note }: ApprovalBarProps) {
  return (
    <section
      aria-label={t('승인')}
      style={{
        display: 'flex',
        alignItems: 'center',
        gap: 'var(--space-4)',
        padding: 'var(--space-4) var(--space-6)',
        border: 'var(--border-overlay)',
        borderRadius: 'var(--radius-md)',
        background: 'var(--color-card)',
      }}
    >
      <div style={{ display: 'flex', flex: 1, flexDirection: 'column', gap: 'var(--space-1)' }}>
        <p className="t-label">{title}</p>
        <p className="t-body-sm t-muted">{meta}</p>
        {note}
      </div>
      <Button variant="outline" size="lg" disabled={disabled || pending} onClick={onReject}>
        {t('거절')}
      </Button>
      <Button variant="primary" size="lg" disabled={disabled || pending} onClick={onApprove}>
        {pending ? t('승인하는 중…') : t('승인하고 배포')}
      </Button>
    </section>
  )
}

export default ApprovalBar
