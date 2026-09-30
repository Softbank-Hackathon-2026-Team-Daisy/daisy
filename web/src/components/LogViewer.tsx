import { useEffect, useRef, useState } from 'react'
import type { EnvType } from './env.ts'
import Icon from './Icon.tsx'
import './LogViewer.css'

// Figma 「05 · Log Viewer」. 전체 환경 로그 — 새 줄이 오면 자동으로 맨 아래로 (위로 스크롤하면 멈춰요)
// 수천 줄에서 느려지면 TanStack Virtual을 붙여요 (ADR-006)
export type LogViewerLine = { key: string | number; time: string; env: EnvType; level: 'INFO' | 'WARN' | 'ERROR'; message: string }

const LEVEL_TONE = { INFO: 'success', WARN: 'warning', ERROR: 'failed' } as const

function LogViewer({ lines, title = '로그 · 전체 환경' }: { lines: LogViewerLine[]; title?: string }) {
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
        <span className="log-viewer__follow t-body-sm">{follow ? '자동 스크롤 켜짐' : '자동 스크롤 꺼짐'}</span>
      </header>
      <div className="log-viewer__body" ref={bodyRef} onScroll={onScroll} role="log">
        {lines.map((l) => (
          <div className="log-viewer__line" key={l.key}>
            <span className="log-viewer__muted">{l.time}</span>
            <span style={{ color: `var(--color-env-${l.env})` }}>{l.env.padEnd(6, ' ')}</span>
            <span style={{ color: `var(--color-status-${LEVEL_TONE[l.level]})` }}>{l.level.padEnd(5, ' ')}</span>
            <span>{l.message}</span>
          </div>
        ))}
      </div>
    </section>
  )
}

export default LogViewer
