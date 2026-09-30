// REST 클라이언트 — Bearer 토큰, 서버 에러 봉투 { error: { code, message, details, retryable } } (ios/SPEC.md R-05)
// 토큰은 메모리에만 둬요 (SPEC.md §3-2). 401이 오면 로그인 화면으로 보내요

export const API_BASE_URL = import.meta.env.VITE_API_BASE_URL ?? ''

// 서버가 열리기 전까지는 목업을 써요. VITE_USE_MOCK=false로 실서버에 붙어요
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
  idempotencyKey?: boolean
  signal?: AbortSignal
}

export async function request<T>(method: string, path: string, options: RequestOptions = {}): Promise<T> {
  const headers: Record<string, string> = { Accept: 'application/json' }
  if (accessToken) headers.Authorization = `Bearer ${accessToken}`
  if (options.body !== undefined) headers['Content-Type'] = 'application/json'
  if (options.idempotencyKey) headers['Idempotency-Key'] = crypto.randomUUID()

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

  if (res.status === 401) onUnauthorized?.()
  if (!res.ok) {
    const body = await res.json().catch(() => null)
    const err = body?.error
    throw new ApiError(res.status, err?.code ?? 'UNKNOWN', err?.message ?? `요청이 실패했어요 (${res.status})`, !!err?.retryable)
  }
  if (res.status === 204) return undefined as T
  return (await res.json()) as T
}
