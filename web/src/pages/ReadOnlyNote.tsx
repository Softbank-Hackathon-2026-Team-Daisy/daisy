// viewer(데모 계정)에게 버튼이 꺼진 이유를 알려줘요. 서버도 403으로 막아요
function ReadOnlyNote({ action }: { action: string }) {
  return (
    <p className="t-body-sm" style={{ color: 'var(--color-warning)' }}>
      읽기 전용 계정이라 {action} 수 없어요.
    </p>
  )
}

export default ReadOnlyNote
