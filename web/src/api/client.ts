// REST 클라이언트 — Bearer 토큰, 서버 에러 봉투 { error: { code, message, details, retryable } } (ios/SPEC.md R-05)
// 토큰은 메모리에만 둬요 (SPEC.md §3-2). 401이 오면 로그인 화면으로 보내요 (로그인 요청 제외)

export const API_BASE_URL = import.meta.env.VITE_API_BASE_URL ?? ''

// 서버가 열리기 전까지는 목업을 써요. VITE_USE_MOCK=false면 서버에 열린 API(endpoints.ts의 SERVER_READY)만 실서버로,
// 아직 없는 API는 목업으로 답해요. 목업으로 답하는 화면에는 MOCK 배지가 붙어요 (루트 AGENTS §4-6)
export const USE_MOCK = import.meta.env.VITE_USE_MOCK !== 'false'

let accessToken: string | null = null
let onUnauthorized: (() => void) | null = null

export function setAccessToken(token: string | null) {
  accessToken = token
}

export function getAccessToken() {
  return accessToken
}

export function setUnauthorizedHandler(handler: () => void) {
  onUnauthorized = handler
}

// 세션 만료(401) — 로그인 요청(/auth/*)의 401은 비밀번호가 틀린 거라 부르지 않아요
export function notifyUnauthorized(path: string) {
  if (!path.startsWith('/auth/')) onUnauthorized?.()
}

// 403 FORBIDDEN은 어느 화면이든 같은 문구로 보여줘요
export const FORBIDDEN_MESSAGE = '읽기 전용 계정이라 할 수 없어요.'

// 화면에 보여줄 에러 문구 — ApiError면 서버 문구(403은 공통 문구), 아니면 fallback
export function errorMessage(e: unknown, fallback: string) {
  if (e instanceof ApiError) return e.status === 403 ? FORBIDDEN_MESSAGE : e.message
  return fallback
}

export class ApiError extends Error {
  status: number
  code: string
  retryable: boolean

  constructor(status: number, code: string, message: string, retryable = false) {
    super(message)
    this.status = status
    this.code = code
    this.retryable = retryable
  }
}

type RequestOptions = {
  body?: unknown
  // 사용자 동작 한 번에 키 하나 — 같은 동작을 다시 보내면 서버가 같은 결과를 돌려줘요 (newIdempotencyKey)
  idempotencyKey?: string
  signal?: AbortSignal
}

export const newIdempotencyKey = () => crypto.randomUUID()

export async function request<T>(method: string, path: string, options: RequestOptions = {}): Promise<T> {
  const headers: Record<string, string> = { Accept: 'application/json' }
  if (accessToken) headers.Authorization = `Bearer ${accessToken}`
  if (options.body !== undefined) headers['Content-Type'] = 'application/json'
  if (options.idempotencyKey) headers['Idempotency-Key'] = options.idempotencyKey

  let res: Response
  try {
    res = await fetch(`${API_BASE_URL}${path}`, {
      method,
      headers,
      body: options.body === undefined ? undefined : JSON.stringify(options.body),
      signal: options.signal,
    })
  } catch {
    throw new ApiError(0, 'NETWORK', '서버에 연결하지 못했어요. 잠시 후 다시 시도해 주세요.', true)
  }

  if (res.status === 401) notifyUnauthorized(path)
  if (!res.ok) {
    const body = await res.json().catch(() => null)
    const err = body?.error
    throw new ApiError(res.status, err?.code ?? 'UNKNOWN', err?.message ?? `요청이 실패했어요 (${res.status})`, !!err?.retryable)
  }
  if (res.status === 204) return undefined as T
  return (await res.json()) as T
}
