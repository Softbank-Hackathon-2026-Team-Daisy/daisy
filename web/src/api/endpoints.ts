import { mockApi, MockError } from '../mocks/api.ts'
import { ApiError, request, USE_MOCK } from './client.ts'
import type {
  AuthToken,
  Build,
  Deployment,
  ListResponse,
  LogLine,
  Manifest,
  Plan,
  PlanDetail,
  Project,
  Script,
  Target,
  TargetStatus,
} from './types.ts'

// 화면이 부르는 API 목록. 경로는 SPEC.md §6 (공용 ID는 ios/SPEC.md §6). USE_MOCK이면 목업이 대신 답해요
// 화면은 이 파일만 부르고, 목업 ↔ 실서버 전환은 여기서만 일어나요

async function mock<T>(fn: () => Promise<T>): Promise<T> {
  try {
    return await fn()
  } catch (e) {
    if (e instanceof MockError) throw new ApiError(e.status, e.code, e.message)
    throw e
  }
}

const q = (params: Record<string, string | undefined>) => {
  const s = new URLSearchParams(Object.entries(params).filter((kv): kv is [string, string] => !!kv[1])).toString()
  return s ? `?${s}` : ''
}

export const api = {
  // R-02
  login: (username: string, password: string) =>
    USE_MOCK ? mock(() => mockApi.login(username, password)) : request<AuthToken>('POST', '/auth/token', { body: { username, password } }),

  // R-09 (가칭, #13) — 서버가 안 받으면 공개 데모 계정 + /auth/token으로 바꿔요
  loginDemo: () => (USE_MOCK ? mock(() => mockApi.login('demo', '')) : request<AuthToken>('POST', '/auth/demo')),

  // A-01
  listProjects: () => (USE_MOCK ? mock(mockApi.listProjects) : request<ListResponse<Project>>('GET', '/projects')),

  // WR-02
  createProject: (repository: string, branch: string) =>
    USE_MOCK
      ? mock(() => mockApi.createProject(repository, branch))
      : request<{ project: Project; manifest: Manifest }>('POST', '/projects', { body: { repository, branch } }),

  // A-12 (#13 가칭)
  getProject: (projectId: string) =>
    USE_MOCK ? mock(() => mockApi.getProject(projectId)) : request<Project>('GET', `/projects/${projectId}`),

  // WR-13
  deleteProject: (projectId: string) =>
    USE_MOCK ? mock(() => mockApi.deleteProject(projectId)) : request<void>('DELETE', `/projects/${projectId}`),

  // A-10 · A-11 (#13 가칭) — W-10 연결 테스트 · 리소스 보기
  testTarget: (targetId: string) =>
    USE_MOCK
      ? mock(() => mockApi.testTarget(targetId))
      : request<{ connected: boolean; message: string }>('POST', `/targets/${targetId}/test`),
  listTargetResources: (targetId: string) =>
    USE_MOCK
      ? mock(() => mockApi.listTargetResources(targetId))
      : request<ListResponse<{ address: string; type: string }>>('GET', `/targets/${targetId}/resources`),

  // WR-03
  getManifest: (projectId: string) =>
    USE_MOCK ? mock(() => mockApi.getManifest(projectId)) : request<Manifest>('GET', `/projects/${projectId}/manifest`),

  // A-02
  getTargetsStatus: (projectId: string) =>
    USE_MOCK ? mock(() => mockApi.getTargetsStatus(projectId)) : request<TargetStatus[]>('GET', `/projects/${projectId}/targets/status`),

  // WR-04
  listTargets: (projectId: string) =>
    USE_MOCK ? mock(() => mockApi.listTargets(projectId)) : request<Target[]>('GET', `/projects/${projectId}/targets`),

  // A-03
  listDeployments: (projectId: string, state?: string) =>
    USE_MOCK
      ? mock(() => mockApi.listDeployments(projectId, state))
      : request<ListResponse<Deployment>>('GET', `/projects/${projectId}/deployments${q({ state })}`),

  // WR-05
  createDeployment: (projectId: string, commit: string, targetIds: string[]) =>
    USE_MOCK
      ? mock(() => mockApi.createDeployment(projectId, commit, targetIds))
      : request<Deployment>('POST', `/projects/${projectId}/deployments`, {
          body: { commit, target_ids: targetIds, strategy: 'recreate' },
          idempotencyKey: true,
        }),

  // A-04
  getDeployment: (id: string) => (USE_MOCK ? mock(() => mockApi.getDeployment(id)) : request<Deployment>('GET', `/deployments/${id}`)),

  // A-05 · WR-06
  getPlan: (id: string) => (USE_MOCK ? mock(() => mockApi.getPlan(id)) : request<Plan>('GET', `/deployments/${id}/plan`)),
  getPlanDetail: (id: string) =>
    USE_MOCK ? mock(() => mockApi.getPlanDetail(id)) : request<PlanDetail[]>('GET', `/deployments/${id}/plan?detail=resources`),

  // API W-01 (웹 화면 ID와 겹쳐서 "API W-01"로 불러요)
  approve: (id: string, decision: 'approve' | 'reject', confirmText?: string) =>
    USE_MOCK
      ? mock(() => mockApi.approve(id, decision))
      : request<Deployment>('POST', `/deployments/${id}/approvals`, {
          body: { kind: 'plan', decision, confirm_text: confirmText },
          idempotencyKey: true,
        }),

  // WR-08 · WR-14
  cancel: (id: string) => (USE_MOCK ? mock(() => mockApi.cancel(id)) : request<Deployment>('POST', `/deployments/${id}/cancel`, { idempotencyKey: true })),
  rollback: (id: string, targetIds: string[], reason?: string) =>
    USE_MOCK
      ? mock(() => mockApi.rollback(id, targetIds))
      : request<Deployment>('POST', `/deployments/${id}/rollback`, { body: { target_ids: targetIds, reason }, idempotencyKey: true }),

  // A-07
  getLogs: (id: string, targetId?: string) =>
    USE_MOCK ? mock(() => mockApi.getLogs(id)) : request<LogLine[]>('GET', `/deployments/${id}/logs${q({ target_id: targetId, tail: '100' })}`),

  // A-06
  listBuilds: (projectId: string) =>
    USE_MOCK ? mock(() => mockApi.listBuilds(projectId)) : request<ListResponse<Build>>('GET', `/projects/${projectId}/builds`),

  // WR-07 · WR-10
  getScript: (deploymentId: string, targetId: string) =>
    USE_MOCK
      ? mock(() => mockApi.getScript(deploymentId, targetId))
      : request<string>('GET', `/deployments/${deploymentId}/targets/${targetId}/script`),
  listScripts: (projectId: string) =>
    USE_MOCK ? mock(() => mockApi.listScripts(projectId)) : request<Script[]>('GET', `/projects/${projectId}/scripts`),
}
