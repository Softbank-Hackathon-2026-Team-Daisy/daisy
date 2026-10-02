// viewer(데모 계정)에게 버튼이 꺼진 이유를 알려줘요. 서버도 403으로 막아요
// 문장은 부르는 쪽에서 통째로 번역해서 넘겨요 — t('읽기 전용 계정이라 배포를 시작할 수 없어요.')
function ReadOnlyNote({ message }: { message: string }) {
  return (
    <p className="t-body-sm" style={{ color: 'var(--color-warning)' }}>
      {message}
    </p>
  )
}

export default ReadOnlyNote
