import type { EnvType } from './env.ts'
import EnvTag from './EnvTag.tsx'
import StatusBadge, { type StatusTone } from './StatusBadge.tsx'

// W-05 · W-05b · W-06의 "환경별 진행 / 상태 / 요약" 한 줄: 환경 태그 · 설명 · 상태
function EnvStatusRow({ env, note, tone, label }: { env: EnvType; note: string; tone: StatusTone; label: string }) {
  return (
    <div style={{ display: 'flex', alignItems: 'center', gap: 'var(--space-3)' }}>
      <EnvTag env={env} />
      <span className="t-mono-sm t-muted" style={{ flex: 1, minWidth: 0 }}>
        {note}
      </span>
      <StatusBadge tone={tone}>{label}</StatusBadge>
    </div>
  )
}

export default EnvStatusRow
