import { t } from '../i18n/index.ts'
import './MockBadge.css'

// 목업 데이터를 보여주는 화면에 반드시 붙여요 (루트 AGENTS.md §4-6). Figma에는 없는 웹 전용 배지예요
// compact: 접힌 사이드바(64px)처럼 좁은 곳에서 작게
function MockBadge({ note, compact }: { note?: string; compact?: boolean }) {
  return (
    <span className={compact ? 'mock-badge mock-badge--compact' : 'mock-badge'} title={note ?? t('서버 대신 목업 데이터를 보여주고 있어요')}>
      MOCK
    </span>
  )
}

export default MockBadge
