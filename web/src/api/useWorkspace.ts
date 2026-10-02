import type { StatusTone } from '../components/StatusBadge.tsx'
import { USE_MOCK } from './client.ts'
import { api, isMocked } from './endpoints.ts'
import type { EnvKind, Health, Project, Role } from './types.ts'
import { pollFor, useProjectLive } from './projectLive.ts'
import { useResource } from './useResource.ts'

// 사이드바가 쓰는 프로젝트 · 환경 · 사용자 · 승인 대기 수 (A-01 · A-02 · R-03 · A-03)
// 목업으로 답하는 값은 mocked로 알려서 MOCK 배지를 붙여요

export type SidebarEnv = { targetId: string; type: EnvKind; name: string; tone: StatusTone; label: string }

const HEALTH: Record<Health, { tone: StatusTone; label: string }> = {
  healthy: { tone: 'success', label: '정상' },
  unhealthy: { tone: 'failed', label: '이상' },
  unknown: { tone: 'queued', label: '확인 전' },
}

/** "sample-monolith" → "SM" */
export const initials = (name: string) =>
  name
    .split(/[-_\s]+/)
    .filter(Boolean)
    .slice(0, 2)
    .map((w) => w[0]!.toUpperCase())
    .join('') || name.slice(0, 2).toUpperCase()

export const ROLE_LABEL: Record<Role, string> = { owner: '관리자', viewer: '읽기 전용' }

export function useProjects() {
  return useResource(() => api.listProjects(), [])
}

export function useWorkspace(projectId: string) {
  const projects = useProjects()
  // SSE 이벤트가 오면(tick) 다시 불러요. 붙어 있으면 폴링은 30초 안전망만
  const { state: live, tick } = useProjectLive()
  const poll = pollFor(live)
  // 프로젝트를 고르기 전(첫 화면으로 보내는 중)에는 환경 · 승인 대기를 부르지 않아요
  const status = useResource(() => (projectId ? api.getTargetsStatus(projectId) : Promise.resolve(null)), [projectId, tick], poll)
  const me = useResource(() => api.me(), [])
  // 승인 대기 목록(A-03)이 아직 목업이면 실서버 프로젝트에 가짜 숫자를 붙이지 않아요
  const pendingMocked = isMocked('listDeployments')
  const pending = useResource(
    () => (projectId && (USE_MOCK || !pendingMocked) ? api.listDeployments(projectId, 'awaiting_approval') : Promise.resolve(null)),
    [projectId, tick],
    poll,
  )

  const list: Project[] = projects.data?.items ?? []
  const project = list.find((p) => p.id === projectId) ?? null
  const envs: SidebarEnv[] = (status.data?.items ?? []).map((t) => ({
    targetId: t.target_id,
    type: t.type,
    name: t.name,
    ...HEALTH[t.health],
  }))

  return {
    projects: list,
    project,
    envs,
    envsMocked: isMocked('getTargetsStatus'),
    user: me.data,
    live,
    pendingApprovals: pending.data?.items.length ?? 0,
  }
}
