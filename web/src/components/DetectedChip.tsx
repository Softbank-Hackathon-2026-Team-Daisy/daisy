import Icon from './Icon.tsx'

// Figma 「04 · Detected Chip」. 저장소에서 찾은 파일 · 설정 (예: Dockerfile, deploy.yaml)
function DetectedChip({ label, found = true }: { label: string; found?: boolean }) {
  return (
    <span
      className="t-label"
      style={{
        display: 'inline-flex',
        alignItems: 'center',
        gap: 'var(--space-1)',
        padding: 'var(--space-1) var(--space-3)',
        borderRadius: 'var(--radius-sm)',
        background: 'var(--color-surface)',
        color: found ? 'var(--color-ink)' : 'var(--color-danger)',
      }}
    >
      <Icon name={found ? 'check' : 'x'} size={14} />
      {label}
    </span>
  )
}

export default DetectedChip
