import type { EnvType } from '../components/env.ts'
import type { StatusTone } from '../components/StatusBadge.tsx'

// MOCK: 사이드바용 프로젝트 · 환경 · 사용자. 서버 API A-01 · A-02 · 인증(R-02)이 열리면 src/api/로 바꿔요 (SPEC.md §6-0)

export type WorkspaceProject = {
  id: string
  name: string
  initials: string
  branch: string
  commit: string
  summary: string
}

export type WorkspaceEnv = {
  type: EnvType
  status: StatusTone
  statusLabel: string
}

export const MOCK_PROJECTS: WorkspaceProject[] = [
  { id: 'prj_monolith', name: 'sample-monolith', initials: 'SM', branch: 'main', commit: 'a1b2c3d', summary: '3개 환경' },
  { id: 'prj_msa', name: 'sample-msa', initials: 'MS', branch: 'main', commit: '9e21f0a', summary: '2개 서비스' },
]

export const MOCK_ENVS: WorkspaceEnv[] = [
  { type: 'onprem', status: 'success', statusLabel: '정상' },
  { type: 'aws', status: 'success', statusLabel: '정상' },
  { type: 'gcp', status: 'running', statusLabel: '배포 중' },
]

export const MOCK_PENDING_APPROVALS = 1

export const MOCK_USER = { name: '김도영', role: '팀장 · Web FE' }
