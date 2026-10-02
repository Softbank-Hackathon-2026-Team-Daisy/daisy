import { useEffect, useRef, useState } from 'react'
import type { ConnectionState } from '../components/ConnectionIndicator.tsx'
import { USE_MOCK } from './client.ts'
import { isMocked } from './endpoints.ts'
import { subscribe, type ServerEvent } from './realtime.ts'

// SSE 채널 하나에 붙어요 (WR-01). 서버 형식은 id(= seq) · event · data(봉투 { seq, ts, deployment_id, target_id, data })
// 이벤트가 오면 onChange로 "다시 불러와" 신호만 줘요 — 화면은 이벤트 내용을 직접 쌓지 않고 스냅샷(A-04 등)을 다시 읽어요.
// 여러 이벤트가 한꺼번에 오면(재생 · resync) 300ms 안의 것은 한 번으로 묶어요. 로그(log.batch)는 onLog로 따로 넘겨요
// 목업 모드이거나 서버에 채널이 없으면 붙지 않고 'polling'을 돌려줘요 → 쓰는 쪽은 5초 폴링을 그대로 해요

export type EventEnvelope = { seq: number; ts: string; deployment_id: string | null; target_id: string | null; data: unknown }
export type LiveLogLine = { seq: number; at: string; target_id: string; level: 'INFO' | 'WARN' | 'ERROR'; message: string }

const BATCH_MS = 300

type Options = {
  onChange?: () => void
  onLog?: (lines: LiveLogLine[]) => void
}

export function useRealtime(path: string | null, { onChange, onLog }: Options = {}): ConnectionState {
  const enabled = !!path && !USE_MOCK && !isMocked(path.startsWith('/projects/') ? 'projectEvents' : 'deploymentEvents')
  const [state, setState] = useState<ConnectionState>('polling')
  // 콜백은 최신 것을 ref에 담아 두고 연결은 다시 맺지 않아요 (렌더 중이 아니라 effect에서 갱신)
  const changeRef = useRef(onChange)
  const logRef = useRef(onLog)
  useEffect(() => {
    changeRef.current = onChange
    logRef.current = onLog
  })

  useEffect(() => {
    if (!enabled || !path) return
    let timer: ReturnType<typeof setTimeout> | undefined
    const changed = () => {
      clearTimeout(timer)
      timer = setTimeout(() => changeRef.current?.(), BATCH_MS)
    }
    const handle = (e: ServerEvent) => {
      if (e.event === 'heartbeat') return
      if (e.event === 'log.batch') {
        const env = e.data as EventEnvelope
        const lines = ((env?.data as { lines?: { target_id: string; level: string; text: string; ts: string }[] })?.lines ?? []).map((l, i) => ({
          seq: env.seq * 1000 + i,
          at: l.ts,
          target_id: l.target_id ?? env.target_id ?? '',
          level: (['INFO', 'WARN', 'ERROR'].includes(l.level?.toUpperCase()) ? l.level.toUpperCase() : 'INFO') as LiveLogLine['level'],
          message: l.text,
        }))
        logRef.current?.(lines)
        return
      }
      changed()
    }
    const stop = subscribe(path, { onEvent: handle, onState: setState, onResync: changed })
    return () => {
      clearTimeout(timer)
      stop()
      setState('polling')
    }
  }, [enabled, path])

  return enabled ? state : 'polling'
}

/** 배포 채널(/deployments/{id}/events) — 단계 · 상태 · plan · 승인 이벤트가 오면 tick이 올라가요 */
export function useDeploymentLive(deploymentId: string, onLog?: (lines: LiveLogLine[]) => void) {
  const [tick, setTick] = useState(0)
  const state = useRealtime(deploymentId ? `/deployments/${deploymentId}/events` : null, {
    onChange: () => setTick((t) => t + 1),
    onLog,
  })
  return { state, tick }
}

/** 배포 채널로 로그를 받는지 — 받으면 A-07(아직 서버에 없음) 대신 SSE log.batch를 써요 */
export const liveLogs = () => !USE_MOCK && !isMocked('deploymentEvents')
