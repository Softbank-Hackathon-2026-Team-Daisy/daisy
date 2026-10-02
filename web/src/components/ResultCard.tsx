import type { ReactNode } from 'react'
import { t } from '../i18n/index.ts'
import type { EnvType } from './env.ts'
import EnvTag from './EnvTag.tsx'
import Icon from './Icon.tsx'
import StatusBadge, { type StatusTone } from './StatusBadge.tsx'

// Figma 「06 · Result Card」. W-08 환경별 결과 — URL · 헬스 · QR 자리(심사위원이 직접 접속)
type ResultCardProps = {
  env: EnvType
  tone: StatusTone
  label: string
  url: string | null
  health: ReactNode
  actions: ReactNode
}

function ResultCard({ env, tone, label, url, health, actions }: ResultCardProps) {
  return (
    <section
      aria-label={t('배포 결과')}
      style={{
        display: 'flex',
        flexDirection: 'column',
        gap: 'var(--space-4)',
        padding: 'var(--space-6)',
        border: 'var(--border)',
        borderRadius: 'var(--radius-md)',
        background: 'var(--color-card)',
        minWidth: 0,
      }}
    >
      <header style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
        <EnvTag env={env} />
        <StatusBadge tone={tone}>{label}</StatusBadge>
      </header>
      <div style={{ display: 'flex', alignItems: 'center', gap: 'var(--space-4)' }}>
        {/* QR 자리 — QR 생성 라이브러리는 아직 넣지 않았어요 (ADR-006) */}
        <span
          aria-hidden="true"
          style={{
            display: 'inline-flex',
            flex: 'none',
            alignItems: 'center',
            justifyContent: 'center',
            width: 72,
            height: 72,
            border: 'var(--border)',
            borderRadius: 'var(--radius-md)',
            background: 'var(--color-bg)',
          }}
        >
          <span style={{ transform: 'scale(2.4)', display: 'inline-flex' }}>
            <Icon name="qr-code" />
          </span>
        </span>
        <div style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-1)', minWidth: 0 }}>
          <span className="t-mono-sm" style={{ overflowWrap: 'anywhere' }}>
            {url ?? '—'}
          </span>
          <span className="t-body-sm">{health}</span>
        </div>
      </div>
      <div style={{ display: 'flex', gap: 'var(--space-2)' }}>{actions}</div>
    </section>
  )
}

export default ResultCard
