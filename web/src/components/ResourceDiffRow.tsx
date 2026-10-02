import { t } from '../i18n/index.ts'

// Figma 「05 · Resource Diff Row」. plan 리소스 한 줄 — 생성(+) · 변경(~) · 삭제(−). 교체(replace)는 삭제로 봐요
type Action = 'create' | 'update' | 'delete' | 'replace'

const LOOK: Record<Action, { symbol: string; tone: string; label: string }> = {
  create: { symbol: '+', tone: 'success', label: '생성' },
  update: { symbol: '~', tone: 'warning', label: '변경' },
  delete: { symbol: '−', tone: 'failed', label: '삭제' },
  replace: { symbol: '±', tone: 'failed', label: '교체(삭제 후 생성)' },
}

function ResourceDiffRow({ action, address, cost }: { action: Action; address: string; cost?: string }) {
  const look = LOOK[action] ?? LOOK.update
  return (
    <div
      style={{
        display: 'flex',
        alignItems: 'center',
        gap: 'var(--space-3)',
        padding: 'var(--space-2) var(--space-3)',
        borderRadius: 'var(--radius-md)',
        background: 'var(--color-status-bg)',
      }}
    >
      <span className="t-mono" style={{ width: 12, color: `var(--color-status-${look.tone})` }} aria-label={t(look.label)}>
        {look.symbol}
      </span>
      <span className="t-mono-sm" style={{ flex: 1, minWidth: 0, overflowWrap: 'anywhere' }}>
        {address}
      </span>
      {cost && <span className="t-mono-sm t-muted">{cost}</span>}
    </div>
  )
}

export default ResourceDiffRow
