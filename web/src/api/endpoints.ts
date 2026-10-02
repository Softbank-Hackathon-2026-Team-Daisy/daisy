import { mockApi, MockError } from '../mocks/api.ts'
import { ApiError, request, USE_MOCK } from './client.ts'
import type {
  AiUsageItem,
  Me,
  AuthToken,
  Build,
  Deployment,
  DeploymentAccepted,
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
// 상태를 바꾸는 요청은 마지막 인자로 Idempotency-Key를 받아요 — 화면은 useAction이 사용자 동작마다 하나 만들어 줘요

// 서버에 열린 API (#38 머지, 10/1). 서버 PR이 머지되면 여기에 이름만 더해요
// 아직 목업: A-07 로그, 스크립트, AI 사용량 호출별, manifest, 프로젝트 연결 · 해제, 연결 테스트 · 리소스
// #42 · #46 · #48: 배포 목록 · 상세 · 생성 · 승인 · 취소 · 재시도 · 롤백 · 환경 목록
const SERVER_READY = new Set<string>([
  'login',
  'me',
  'listProjects',
  'getProject',
  'getTargetsStatus',
  'listBuilds',
  'listTargets',
  'listDeployments',
  'getDeployment',
  'createDeployment',
  'approve',
  'cancel',
  'retry',
  'rollback',
  // #51: A-05 plan 요약 · WR-06 리소스 목록 (W-06)
  'getPlan',
  'getPlanDetail',
  // #42: SSE 채널 (useRealtime)
  'projectEvents',
  'deploymentEvents',
])

/** 이 API를 목업으로 답하는지 — 화면이 MOCK 배지를 붙일지 정할 때 써요 */
export const isMocked = (...names: string[]) => USE_MOCK || names.some((n) => !SERVER_READY.has(n))

const live = (name: string) => !USE_MOCK && SERVER_READY.has(name)

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
    !live('login') ? mock(() => mockApi.login(username, password)) : request<AuthToken>('POST', '/auth/token', { body: { username, password } }),

  // R-03 GET /auth/me — 사이드바 사용자 이름 · 역할
  me: () => (!live('me') ? mock(mockApi.me) : request<Me>('GET', '/auth/me')),

  // R-09 데모 로그인 — 서버는 /auth/demo를 만들지 않아요 (#13 10/1 답). 실서버에서는 따로 받은 viewer 계정으로
  // 로그인 폼을 써야 해서, 비밀번호를 웹에 넣지 않고 안내만 해요
  loginDemo: () =>
    USE_MOCK
      ? mock(() => mockApi.login('demo', ''))
      : Promise.reject(new ApiError(400, 'DEMO_ACCOUNT', '데모 계정은 따로 받은 아이디 · 비밀번호로 위 폼에서 로그인해 주세요.')),

  // A-01
  listProjects: () => (!live('listProjects') ? mock(mockApi.listProjects) : request<ListResponse<Project>>('GET', '/projects')),

  // WR-02
  createProject: (repository: string, branch: string) =>
    !live('createProject')
      ? mock(() => mockApi.createProject(repository, branch))
      : request<{ project: Project; manifest: Manifest }>('POST', '/projects', { body: { repository, branch } }),

  // A-12 (#13 가칭)
  getProject: (projectId: string) =>
    !live('getProject') ? mock(() => mockApi.getProject(projectId)) : request<Project>('GET', `/projects/${projectId}`),

  // WR-13
  deleteProject: (projectId: string) =>
    !live('deleteProject') ? mock(() => mockApi.deleteProject(projectId)) : request<void>('DELETE', `/projects/${projectId}`),

  // A-10 · A-11 (#13 가칭) — W-10 연결 테스트 · 리소스 보기
  testTarget: (targetId: string) =>
    !live('testTarget')
      ? mock(() => mockApi.testTarget(targetId))
      : request<{ connected: boolean; message: string }>('POST', `/targets/${targetId}/test`),
  listTargetResources: (targetId: string) =>
    !live('listTargetResources')
      ? mock(() => mockApi.listTargetResources(targetId))
      : request<ListResponse<{ address: string; type: string }>>('GET', `/targets/${targetId}/resources`),

  // WR-03
  getManifest: (projectId: string) =>
    !live('getManifest') ? mock(() => mockApi.getManifest(projectId)) : request<Manifest>('GET', `/projects/${projectId}/manifest`),

  // A-02
  getTargetsStatus: (projectId: string) =>
    !live('getTargetsStatus') ? mock(() => mockApi.getTargetsStatus(projectId)) : request<ListResponse<TargetStatus>>('GET', `/projects/${projectId}/targets/status`),

  // WR-04
  listTargets: (projectId: string) =>
    !live('listTargets') ? mock(() => mockApi.listTargets(projectId)) : request<ListResponse<Target>>('GET', `/projects/${projectId}/targets`),

  // A-03
  listDeployments: (projectId: string, state?: string) =>
    !live('listDeployments')
      ? mock(() => mockApi.listDeployments(projectId, state))
      : request<ListResponse<Deployment>>('GET', `/projects/${projectId}/deployments${q({ state })}`),

  // WR-05 — 빌드는 source_version_id로 골라요 (#36 · #42). commit은 화면 표시 · 목업용
  createDeployment: (projectId: string, build: { source_version_id?: string; commit: string }, targetIds: string[], key: string) =>
    !live('createDeployment')
      ? mock(() => mockApi.createDeployment(projectId, build.commit, targetIds))
      : request<DeploymentAccepted>('POST', `/projects/${projectId}/deployments`, {
          body: { source_version_id: build.source_version_id, target_ids: targetIds },
          idempotencyKey: key,
        }),

  // 실패한 환경만 새 배포로 다시 시도 (W-05b · W-08). 원래 배포와 같은 빌드를 서버가 골라요 (10/2 확정, #42)
  retry: (id: string, targetIds: string[], key: string) =>
    !live('retry')
      ? mock(() => mockApi.retry(id, targetIds))
      : request<DeploymentAccepted>('POST', `/deployments/${id}/retry`, { body: { target_ids: targetIds }, idempotencyKey: key }),

  // A-04
  getDeployment: (id: string) => (!live('getDeployment') ? mock(() => mockApi.getDeployment(id)) : request<Deployment>('GET', `/deployments/${id}`)),

  // A-05 · WR-06
  getPlan: (id: string) => (!live('getPlan') ? mock(() => mockApi.getPlan(id)) : request<Plan>('GET', `/deployments/${id}/plan`)),
  getPlanDetail: (id: string) =>
    !live('getPlanDetail') ? mock(() => mockApi.getPlanDetail(id)) : request<PlanDetail[]>('GET', `/deployments/${id}/plan?detail=resources`),

  // API W-01 (웹 화면 ID와 겹쳐서 "API W-01"로 불러요)
  // 화면에서 본 승인 대기 환경만 items에 담아요. 비면 서버가 400 (#40 · #42)
  approve: (
    id: string,
    decision: 'approve' | 'reject',
    confirmText: string | undefined,
    items: { target_id: string; approval_id: string }[],
    key: string,
  ) =>
    !live('approve')
      ? mock(() => mockApi.approve(id, decision))
      : request<DeploymentAccepted>('POST', `/deployments/${id}/approvals`, {
          body: { decision, confirm_text: confirmText, items },
          idempotencyKey: key,
        }),

  // WR-08 · WR-14
  cancel: (id: string, targetIds: string[], key: string) =>
    !live('cancel')
      ? mock(() => mockApi.cancel(id))
      : request<DeploymentAccepted>('POST', `/deployments/${id}/cancel`, { body: { target_ids: targetIds }, idempotencyKey: key }),
  rollback: (id: string, targetIds: string[], reason: string | undefined, key: string) =>
    !live('rollback')
      ? mock(() => mockApi.rollback(id, targetIds))
      : request<DeploymentAccepted>('POST', `/deployments/${id}/rollback`, { body: { target_ids: targetIds, reason }, idempotencyKey: key }),

  // A-07
  getLogs: (id: string, targetId?: string) =>
    !live('getLogs') ? mock(() => mockApi.getLogs(id)) : request<LogLine[]>('GET', `/deployments/${id}/logs${q({ target_id: targetId, tail: '100' })}`),

  // AI 사용량 호출별 기록 (#13 서버 결정, 합계는 A-05 plan 응답)
  listAiUsage: (projectId: string, deploymentId: string) =>
    !live('listAiUsage')
      ? mock(() => mockApi.listAiUsage(projectId, deploymentId))
      : request<ListResponse<AiUsageItem>>('GET', `/projects/${projectId}/ai-usage${q({ deployment_id: deploymentId })}`),

  // A-06
  listBuilds: (projectId: string) =>
    !live('listBuilds') ? mock(() => mockApi.listBuilds(projectId)) : request<ListResponse<Build>>('GET', `/projects/${projectId}/builds`),

  // WR-07 · WR-10
  getScript: (deploymentId: string, targetId: string) =>
    !live('getScript')
      ? mock(() => mockApi.getScript(deploymentId, targetId))
      : request<Script>('GET', `/deployments/${deploymentId}/targets/${targetId}/script`),
  listScripts: (projectId: string) =>
    !live('listScripts') ? mock(() => mockApi.listScripts(projectId)) : request<Script[]>('GET', `/projects/${projectId}/scripts`),
}

/** 목업으로 답하는 API가 하나라도 있으면 true — 화면 MOCK 배지 기본값 */
export const SOME_MOCKED = USE_MOCK || Object.keys(api).some((n) => !SERVER_READY.has(n))

// SSE 채널 경로 (WR-01, #42) — 연결은 useRealtime이 해요
export const events = {
  project: (projectId: string) => `/projects/${projectId}/events`,
  deployment: (deploymentId: string) => `/deployments/${deploymentId}/events`,
}
