import { useEffect, useRef, useState } from 'react'
import { t } from '../i18n/index.ts'
import type { EnvType } from './env.ts'
import Icon from './Icon.tsx'
import './LogViewer.css'

// Figma 「05 · Log Viewer」. 전체 환경 로그 — 새 줄이 오면 자동으로 맨 아래로 (위로 스크롤하면 멈춰요)
// 수천 줄에서 느려지면 TanStack Virtual을 붙여요 (ADR-006)
// env가 null이면 특정 환경이 아닌 실행 공통(Jenkins 콘솔) 줄이에요 (#56)
export type LogViewerLine = { key: string | number; time: string; env: EnvType | null; level: 'INFO' | 'WARN' | 'ERROR'; message: string }

// ISO 시각이면 HH:MM:SS로
const clock = (time: string) => (time.includes('T') ? new Date(time).toTimeString().slice(0, 8) : time)

const LEVEL_TONE = { INFO: 'success', WARN: 'warning', ERROR: 'failed' } as const

function LogViewer({ lines, title: titleProp }: { lines: LogViewerLine[]; title?: string }) {
  const title = titleProp ?? t('로그 · 전체 환경')
  const bodyRef = useRef<HTMLDivElement>(null)
  const [follow, setFollow] = useState(true)

  useEffect(() => {
    const el = bodyRef.current
    if (el && follow) el.scrollTop = el.scrollHeight
  }, [lines, follow])

  const onScroll = () => {
    const el = bodyRef.current
    if (!el) return
    setFollow(el.scrollHeight - el.scrollTop - el.clientHeight < 8)
  }

  return (
    <section className="log-viewer" aria-label={title}>
      <header className="log-viewer__header">
        <Icon name="terminal" size={16} />
        <span className="t-label">{title}</span>
        <span className="log-viewer__follow t-body-sm">{follow ? t('자동 스크롤 켜짐') : t('자동 스크롤 꺼짐')}</span>
      </header>
      <div className="log-viewer__body" ref={bodyRef} onScroll={onScroll} role="log">
        {lines.map((l) => (
          <div className="log-viewer__line" key={l.key}>
            <span className="log-viewer__muted">{clock(l.time)}</span>
            <span style={{ color: l.env ? `var(--color-env-${l.env})` : 'var(--color-ink-muted)' }}>{(l.env ?? 'common').padEnd(6, ' ')}</span>
            <span style={{ color: `var(--color-status-${LEVEL_TONE[l.level]})` }}>{l.level.padEnd(5, ' ')}</span>
            <span>{l.message}</span>
          </div>
        ))}
      </div>
    </section>
  )
}

export default LogViewer
