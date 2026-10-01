// W-12 숫자 타일: 이름 · 큰 숫자 · 보조 설명 (차트는 쓰지 않아요)
function StatTile({ label, value, hint }: { label: string; value: string; hint: string }) {
  return (
    <section
      aria-label={label}
      style={{
        display: 'flex',
        flexDirection: 'column',
        gap: 'var(--space-1)',
        padding: 20,
        border: 'var(--border)',
        borderRadius: 'var(--radius-md)',
        background: 'var(--color-card)',
      }}
    >
      <span className="t-label t-muted">{label}</span>
      <span className="t-h1">{value}</span>
      <span className="t-mono-sm t-muted">{hint}</span>
    </section>
  )
}

export default StatTile
