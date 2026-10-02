import type { ReactNode } from 'react'
import { t } from '../i18n/index.ts'
import type { EnvType } from './env.ts'
import EnvTag from './EnvTag.tsx'
import Icon from './Icon.tsx'
import QrCode from './QrCode.tsx'
import StatusBadge, { type StatusTone } from './StatusBadge.tsx'

// Figma 「06 · Result Card」. W-08 환경별 결과 — URL · 헬스 · QR(심사위원이 휴대폰으로 바로 접속)
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
        {url ? (
          <QrCode value={url} size={72} label={t('{url} QR 코드', { url })} />
        ) : (
          // URL이 아직 없으면 흐린 자리만 보여요
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
              color: 'var(--color-ink-muted)',
            }}
          >
            <span style={{ transform: 'scale(2.4)', display: 'inline-flex' }}>
              <Icon name="qr-code" />
            </span>
          </span>
        )}
        <div style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-1)', minWidth: 0 }}>
          {/* URL을 누르면 새 탭에서 열려요 — 심사위원이 바로 접속 (10/2 회의) */}
          {url ? (
            <a className="t-mono-sm" href={url} target="_blank" rel="noopener noreferrer">
              <BreakableUrl url={url} />
            </a>
          ) : (
            <span className="t-mono-sm">
              —
            </span>
          )}
          <span className="t-body-sm">{health}</span>
        </div>
      </div>
      <div style={{ display: 'flex', gap: 'var(--space-2)' }}>{actions}</div>
    </section>
  )
}

// 긴 URL은 '.' · '/' 뒤에서만 줄을 바꿔요 — 단어 중간("unibloom.clo / ud")에서 끊기지 않게
export function BreakableUrl({ url }: { url: string }) {
  const parts = url.split(/(?<=[./])/)
  return (
    <>
      {parts.map((part, i) => (
        <span key={i}>
          {part}
          {i < parts.length - 1 && <wbr />}
        </span>
      ))}
    </>
  )
}

export default ResultCard
