import { Link } from 'react-router'
import { relativeTime, shortCommit } from '../utils/format.ts'
import Avatar from './Avatar.tsx'
import StatusBadge, { type StatusTone } from './StatusBadge.tsx'
import './RunListItem.css'

// Figma 「04 · Run List Item」. 실행(배포 · 빌드) 한 줄: 상태 · 커밋 · 메시지 · 작성자 · 시각
type RunListItemProps = {
  tone: StatusTone
  label: string
  commit: string
  message: string
  author: string
  at: string
  to?: string
}

function RunListItem({ tone, label, commit, message, author, at, to }: RunListItemProps) {
  const body = (
    <>
      <StatusBadge tone={tone}>{label}</StatusBadge>
      <span className="t-mono-sm">{shortCommit(commit)}</span>
      <span className="run-item__message">{message}</span>
      <Avatar type="human" name={author} />
      <span className="run-item__time t-body-sm t-muted">{relativeTime(at)}</span>
    </>
  )
  return to ? (
    <Link to={to} className="run-item run-item--link">
      {body}
    </Link>
  ) : (
    <div className="run-item">{body}</div>
  )
}

export default RunListItem
