import { useLayoutEffect, useRef, useState } from 'react'
import { t } from '../i18n/index.ts'
import { ENV_LABEL, type EnvType } from './env.ts'
import Icon from './Icon.tsx'
import type { StatusTone } from './StatusBadge.tsx'
import Tabs from './Tabs.tsx'
import './LogViewer.css'

// Figma 「05 · Log Viewer」. 전체 환경 로그 — 새 줄이 오면 자동으로 맨 아래로 (위로 스크롤하면 멈춰요)
// 수천 줄에서 느려지면 TanStack Virtual을 붙여요 (ADR-006)
// env가 null이면 특정 환경이 아닌 실행 공통(Jenkins 콘솔) 줄이에요 (#56) — 「전체」 탭에만 나와요
// envs를 주면 [전체] [환경…] 탭이 생겨요. 자동 스크롤은 탭마다 따로 기억해요
export type LogViewerLine = { key: string | number; time: string; env: EnvType | null; level: 'INFO' | 'WARN' | 'ERROR'; message: string }
export type LogViewerEnv = { env: EnvType; tone: StatusTone; toneLabel?: string }
export type LogViewerTab = 'all' | EnvType

// ISO 시각이면 HH:MM:SS로
const clock = (time: string) => (time.includes('T') ? new Date(time).toTimeString().slice(0, 8) : time)

const LEVEL_TONE = { INFO: 'success', WARN: 'warning', ERROR: 'failed' } as const

type LogViewerProps = {
  lines: LogViewerLine[]
  title?: string
  envs?: LogViewerEnv[]
  tab?: LogViewerTab
  onTabChange?: (tab: LogViewerTab) => void
}

function LogViewer({ lines, title: titleProp, envs, tab: tabProp, onTabChange }: LogViewerProps) {
  const title = titleProp ?? t('로그 · 전체 환경')
  const bodyRef = useRef<HTMLDivElement>(null)
  const [ownTab, setOwnTab] = useState<LogViewerTab>('all')
  const tab = envs?.length ? (tabProp ?? ownTab) : 'all'
  const setTab = (next: LogViewerTab) => (onTabChange ? onTabChange(next) : setOwnTab(next))
  // 탭마다 자동 스크롤 여부 · 멈춘 위치를 기억해요
  const [follow, setFollow] = useState<Partial<Record<LogViewerTab, boolean>>>({})
  const scrollTops = useRef<Partial<Record<LogViewerTab, number>>>({})
  const following = follow[tab] ?? true

  const shown = tab === 'all' ? lines : lines.filter((l) => l.env === tab)

  useLayoutEffect(() => {
    const el = bodyRef.current
    if (!el) return
    el.scrollTop = following ? el.scrollHeight : (scrollTops.current[tab] ?? 0)
  }, [shown.length, tab, following])

  const onScroll = () => {
    const el = bodyRef.current
    if (!el) return
    scrollTops.current[tab] = el.scrollTop
    const atBottom = el.scrollHeight - el.scrollTop - el.clientHeight < 8
    if (atBottom !== following) setFollow((prev) => ({ ...prev, [tab]: atBottom }))
  }

  const countOf = (env: EnvType) => lines.reduce((n, l) => (l.env === env ? n + 1 : n), 0)

  return (
    <section className="log-viewer" aria-label={title}>
      <header className="log-viewer__header">
        <Icon name="terminal" size={16} />
        <span className="t-label">{title}</span>
        <span className="log-viewer__follow t-body-sm">{following ? t('자동 스크롤 켜짐') : t('자동 스크롤 꺼짐')}</span>
      </header>
      {!!envs?.length && (
        <div className="log-viewer__tabs">
          <Tabs
            label={t('로그 환경')}
            idPrefix="log-tab"
            value={tab}
            onChange={(id) => setTab(id as LogViewerTab)}
            items={[
              { id: 'all', label: t('전체'), count: lines.length },
              ...envs.map((e) => ({ id: e.env, label: t(ENV_LABEL[e.env]), env: e.env, count: countOf(e.env), tone: e.tone, toneLabel: e.toneLabel })),
            ]}
          />
        </div>
      )}
      <div
        className="log-viewer__body"
        ref={bodyRef}
        onScroll={onScroll}
        role="log"
        id={envs?.length ? `log-tab-panel-${tab}` : undefined}
        aria-labelledby={envs?.length ? `log-tab-${tab}` : undefined}
      >
        {shown.length === 0 && <span className="log-viewer__muted">{t('아직 로그가 없어요')}</span>}
        {shown.map((l) => (
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
