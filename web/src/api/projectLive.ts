import { createContext, useContext } from 'react'
import type { ConnectionState } from '../components/ConnectionIndicator.tsx'
import { POLL_MS, POLL_MS_LIVE } from './useResource.ts'

// 프로젝트 채널(/projects/{id}/events) 하나를 AppLayout이 붙고, 화면들이 나눠 써요
// tick은 이벤트가 올 때마다 올라가요 → 화면은 useResource deps에 넣어 다시 불러요
export type ProjectLive = { state: ConnectionState; tick: number }

export const ProjectLiveContext = createContext<ProjectLive>({ state: 'polling', tick: 0 })

export function useProjectLive() {
  return useContext(ProjectLiveContext)
}

/** SSE가 붙어 있으면 폴링은 30초 안전망만, 아니면 5초 */
export const pollFor = (state: ConnectionState) => (state === 'connected' ? POLL_MS_LIVE : POLL_MS)
