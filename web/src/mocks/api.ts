import type { AuthToken, Deployment, DeploymentTarget, ListResponse } from '../api/types.ts'
import * as s from './scenario.ts'

// MOCK: 서버 대신 응답하는 목업 API. 모양은 SPEC.md §6과 같아요. 서버가 열리면 VITE_USE_MOCK=false로 꺼요
// "dep_live"는 시간이 흐르면 상태가 바뀌어서, 목업만으로 W-04 → W-08 흐름을 끝까지 볼 수 있어요

const wait = (ms = 250) => new Promise((r) => setTimeout(r, ms))
const clone = <T>(v: T): T => structuredClone(v)

class MockError extends Error {
  status: number
  code: string
  constructor(status: number, code: string, message: string) {
    super(message)
    this.status = status
    this.code = code
  }
}

// ── 시간에 따라 진행하는 배포 (dep_live) ──
let live: { startedAt: number; approvedAt: number | null } | null = null
let buildStartedAt: number | null = null
let connectedAt: number | null = null

function liveDeployment(): Deployment {
  if (!live) throw new MockError(404, 'NOT_FOUND', '배포를 찾을 수 없어요')
  const t = (Date.now() - live.startedAt) / 1000
  const base = clone(s.deployments.dep_generate)
  const set = (i: number, patch: Partial<DeploymentTarget>) => Object.assign(base.targets[i], patch)
  base.id = 'dep_live'
  base.pending_approval = null

  if (live.approvedAt === null) {
    if (t < 3) {
      // L-02: 생성 시작 전 (작업 큐 대기)
      base.state = 'queued'
      base.targets.forEach((_, i) => set(i, { state: 'waiting', step: 'generate', attempt: 1, error_summary: null }))
    } else if (t < 7) {
      base.state = 'running'
      set(0, { state: 'validating', step: 'plan', error_summary: null })
      set(1, { state: 'generating', step: 'generate', attempt: 1, error_summary: null })
      set(2, { state: 'generating', step: 'generate' })
    } else if (t < 13) {
      // W-05와 같은 모습: AWS 시도 2/3
    } else {
      base.state = 'awaiting_approval'
      base.pending_approval = { approval_id: 'apv_live', kind: 'plan' }
      base.targets.forEach((_, i) => set(i, { state: 'awaiting_approval', step: 'risk_check', error_summary: null }))
    }
    return base
  }

  const a = (Date.now() - live.approvedAt) / 1000
  const result = clone(s.deployments.dep_result)
  result.id = 'dep_live'
  if (a < 3) {
    // L-03: apply 준비 중 (승인 접수, 락 · 작업 디렉터리 준비)
    const preparing = clone(s.deployments.dep_approve)
    preparing.id = 'dep_live'
    preparing.state = 'running'
    preparing.pending_approval = null
    return preparing
  }
  if (a < 9) {
    const apply = clone(s.deployments.dep_apply)
    apply.id = 'dep_live'
    return apply
  }
  return result
}

function findDeployment(id: string): Deployment {
  if (id === 'dep_live') return liveDeployment()
  const d = s.deployments[id] ?? s.history.find((h) => h.id === id)
  if (!d) throw new MockError(404, 'NOT_FOUND', '배포를 찾을 수 없어요')
  return clone(d)
}

export const mockApi = {
  async login(username: string, password: string): Promise<AuthToken> {
    await wait(400)
    if (username === 'demo') return { access_token: 'mock-viewer', expires_at: new Date(Date.now() + 3_600_000).toISOString(), role: 'viewer' }
    if (!username || password !== 'daisy') throw new MockError(401, 'UNAUTHENTICATED', '아이디나 비밀번호가 맞지 않아요')
    return { access_token: 'mock-admin', expires_at: new Date(Date.now() + 3_600_000).toISOString(), role: 'admin' }
  },
  async listProjects() {
    await wait()
    return { items: clone(s.projects), next_cursor: null }
  },
  async getTargetsStatus(_projectId: string) {
    await wait()
    return clone(s.targetStatus)
  },
  async listTargets(_projectId: string) {
    await wait()
    return clone(s.targets)
  },
  async listDeployments(_projectId: string, state?: string): Promise<ListResponse<Deployment>> {
    await wait()
    const items = clone(s.history).filter((d) => !state || d.state === state)
    return { items, next_cursor: null }
  },
  async getDeployment(id: string) {
    await wait(150)
    return findDeployment(id)
  },
  async createDeployment(_projectId: string, _commit: string, _targetIds: string[]) {
    await wait(400)
    live = { startedAt: Date.now(), approvedAt: null }
    return liveDeployment()
  },
  async approve(id: string, decision: 'approve' | 'reject') {
    await wait(400)
    if (id === 'dep_live' && live && decision === 'approve') live.approvedAt = Date.now()
    return findDeployment(id)
  },
  async cancel(id: string) {
    await wait()
    return findDeployment(id)
  },
  async rollback(_id: string, _targetIds: string[]) {
    await wait(400)
    live = { startedAt: Date.now() - 10_000, approvedAt: null }
    const d = liveDeployment()
    d.kind = 'rollback'
    d.rolled_back_from = 'dep_41'
    return d
  },
  async getPlan(_id: string) {
    await wait()
    return clone(s.plan)
  },
  async getPlanDetail(_id: string) {
    await wait()
    return clone(s.planDetail)
  },
  async getLogs(_id: string) {
    await wait()
    return clone(s.logs)
  },
  // 처음 부른 뒤 6초가 지나면 빌드가 끝나요 (W-03 → W-04로 넘어가는 모습을 보려고)
  async listBuilds(_projectId: string) {
    await wait()
    // L-01: 저장소를 막 연결했으면 첫 빌드가 4초 뒤에 나타나요
    if (connectedAt && Date.now() - connectedAt < 4000) return { items: [], next_cursor: null }
    buildStartedAt ??= Date.now()
    const items = clone(s.builds)
    if (Date.now() - buildStartedAt > 6000) {
      items[0].pipeline.status = 'success'
      items[0].pipeline.steps = items[0].pipeline.steps?.map((st) => ({ ...st, state: 'done' }))
    }
    return { items, next_cursor: null }
  },
  async getScript(_id: string, _targetId: string) {
    await wait()
    return s.generatedScript
  },
  async listScripts(_projectId: string) {
    await wait()
    return clone(s.scripts)
  },
  async getManifest(_projectId: string) {
    await wait()
    return clone(s.manifest)
  },
  async createProject(repository: string, branch: string) {
    await wait(600)
    connectedAt = Date.now()
    buildStartedAt = connectedAt + 4000
    return { project: { ...clone(s.projects[0]), repository, branch }, manifest: clone(s.manifest) }
  },
}

export { MockError }
