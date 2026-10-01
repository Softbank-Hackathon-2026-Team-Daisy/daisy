// 화면 뼈대 — 10/1 ~ 10/2에 와이어프레임대로 채우면서 하나씩 지워요 (SPEC.md §5)
type PlaceholderProps = {
  id: string
  title: string
  note?: string
}

function Placeholder({ id, title, note }: PlaceholderProps) {
  return (
    <section style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-2)' }}>
      <p className="t-overline t-muted">{id}</p>
      <h1 className="t-h1">{title}</h1>
      <p className="t-body-sm t-muted">{note ?? '뼈대만 있어요. 와이어프레임대로 채울 예정이에요.'}</p>
    </section>
  )
}

export default Placeholder
