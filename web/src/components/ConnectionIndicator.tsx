import Icon from './Icon.tsx'
import './ConnectionIndicator.css'

// Figma 「05 · Connection Indicator」. 실시간(SSE) 연결 상태. 접힌 사이드바에서는 점만 보여줘요
export type ConnectionState = 'connected' | 'reconnecting' | 'disconnected'

const LABEL: Record<ConnectionState, string> = {
  connected: '실시간 연결됨',
  reconnecting: '재연결 중…',
  disconnected: '연결 끊김 · 다시 시도',
}

type ConnectionIndicatorProps = {
  state: ConnectionState
  compact?: boolean
  onRetry?: () => void
}

function ConnectionIndicator({ state, compact, onRetry }: ConnectionIndicatorProps) {
  if (compact) {
    return <span className={`connection-dot connection--${state}`} role="status" aria-label={LABEL[state]} />
  }
  const clickable = state === 'disconnected' && onRetry
  const Tag = clickable ? 'button' : 'span'
  return (
    <Tag
      className={`connection connection--${state}`}
      role={clickable ? undefined : 'status'}
      type={clickable ? 'button' : undefined}
      onClick={clickable ? onRetry : undefined}
    >
      <Icon name="signal" size={16} />
      {LABEL[state]}
    </Tag>
  )
}

export default ConnectionIndicator
