import './MockBadge.css'

// 목업 데이터를 보여주는 화면에 반드시 붙여요 (루트 AGENTS.md §4-6). Figma에는 없는 웹 전용 배지예요
function MockBadge({ note }: { note?: string }) {
  return (
    <span className="mock-badge" title={note ?? '서버 대신 목업 데이터를 보여주고 있어요'}>
      MOCK
    </span>
  )
}

export default MockBadge
