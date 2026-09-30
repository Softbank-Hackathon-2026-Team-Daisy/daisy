import type { ReactNode } from 'react'
import './StatusBadge.css'

// Figma 「02 Core · Status Badge」. 서버 상태 값 → 톤 매핑은 화면에서 해요 (SPEC.md §2-5)
export type StatusTone = 'queued' | 'running' | 'success' | 'failed' | 'warning' | 'rolledback'

const DEFAULT_LABEL: Record<StatusTone, string> = {
  queued: '대기 중',
  running: '배포 중',
  success: '성공',
  failed: '실패',
  warning: '주의',
  rolledback: '롤백됨',
}

type StatusBadgeProps = {
  tone: StatusTone
  // 기본 문구와 다를 때만 (예: "승인 대기", "일부 성공")
  children?: ReactNode
}

function StatusBadge({ tone, children }: StatusBadgeProps) {
  return (
    <span className={`status-badge status-badge--${tone}`}>
      <span className="status-badge__dot" aria-hidden="true" />
      {children ?? DEFAULT_LABEL[tone]}
    </span>
  )
}

export default StatusBadge
