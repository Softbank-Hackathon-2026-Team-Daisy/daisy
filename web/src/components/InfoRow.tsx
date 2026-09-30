import type { ReactNode } from 'react'

// Figma 「04 · Info Row」. 왼쪽 이름(120px) · 오른쪽 값(mono), 아래 1px 줄
function InfoRow({ label, children }: { label: string; children: ReactNode }) {
  return (
    <div style={{ display: 'flex', alignItems: 'center', gap: 'var(--space-4)', padding: 'var(--space-2) 0', borderBottom: 'var(--border)' }}>
      <span className="t-muted" style={{ flex: 'none', width: 120 }}>
        {label}
      </span>
      <span className="t-mono" style={{ minWidth: 0, overflowWrap: 'anywhere' }}>
        {children}
      </span>
    </div>
  )
}

export default InfoRow
