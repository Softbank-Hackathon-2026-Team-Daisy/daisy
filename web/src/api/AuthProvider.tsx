import { useEffect, useMemo, useState, type ReactNode } from 'react'
import { useLocation, useNavigate } from 'react-router'
import { AuthContext, type AuthState } from './auth.ts'
import { ApiError, setAccessToken, setUnauthorizedHandler } from './client.ts'
import { api, isMocked } from './endpoints.ts'
import type { AuthToken } from './types.ts'

// 로그인 상태를 앱 전체에 나눠요. 401이 오면 토큰을 지우고 로그인 화면(세션 만료 안내)으로 보내요
// 토큰은 sessionStorage(탭 단위)에 둬서 새로고침해도 로그인이 남고, 탭을 닫으면 사라져요 (SPEC §3-2, #102)
const STORAGE_KEY = 'unibloom.session'
type Saved = { token: string; role: AuthToken['role']; expires_at?: string }

function load(): Saved | null {
  try {
    const raw = sessionStorage.getItem(STORAGE_KEY)
    if (!raw) return null
    const saved = JSON.parse(raw) as Saved
    if (!saved?.token || !saved.role) return null
    if (saved.expires_at && new Date(saved.expires_at).getTime() <= Date.now()) {
      sessionStorage.removeItem(STORAGE_KEY)
      return null
    }
    return saved
  } catch {
    return null
  }
}

function save(saved: Saved | null) {
  try {
    if (saved) sessionStorage.setItem(STORAGE_KEY, JSON.stringify(saved))
    else sessionStorage.removeItem(STORAGE_KEY)
  } catch {
    // 저장소를 못 쓰면 메모리에만 둬요 (새로고침하면 다시 로그인)
  }
}

// 첫 화면을 그리기 전에 저장된 토큰을 client.ts에 넣어요 — 첫 요청부터 Bearer가 붙게
function restore(): AuthToken['role'] | null {
  const saved = load()
  if (!saved) return null
  setAccessToken(saved.token)
  return saved.role
}

function AuthProvider({ children }: { children: ReactNode }) {
  const [role, setRole] = useState<AuthToken['role'] | null>(restore)
  const navigate = useNavigate()
  const { pathname } = useLocation()

  useEffect(() => {
    setUnauthorizedHandler(() => {
      setAccessToken(null)
      save(null)
      setRole(null)
      navigate(`/login?expired=1&next=${encodeURIComponent(pathname)}`, { replace: true })
    })
  }, [navigate, pathname])

  // 저장된 토큰으로 켰으면 /auth/me로 역할을 다시 확인해요. 401이면 지워요 (/auth/*는 공통 401 처리에서 빠져서 여기서)
  // 목업 모드의 me는 로그인한 계정을 기억하지 못해서(새로고침하면 초기화) 저장된 역할을 그대로 써요
  useEffect(() => {
    if (!role || isMocked('me')) return
    let alive = true
    api
      .me()
      .then((me) => {
        if (!alive) return
        setRole(me.role)
        const saved = load()
        if (saved) save({ ...saved, role: me.role })
      })
      .catch((e) => {
        if (!alive || !(e instanceof ApiError) || e.status !== 401) return
        setAccessToken(null)
        save(null)
        setRole(null)
      })
    return () => {
      alive = false
    }
    // 앱을 켤 때 한 번만
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

  const value = useMemo<AuthState>(
    () => ({
      role,
      signIn: (token) => {
        setAccessToken(token.access_token)
        save({ token: token.access_token, role: token.role, expires_at: token.expires_at })
        setRole(token.role)
      },
      // 로그아웃하면 AppLayout이 로그인 화면(?next=지금 화면)으로 보내요 — 다른 계정으로 들어와도 같은 화면으로 돌아와요
      signOut: () => {
        setAccessToken(null)
        save(null)
        setRole(null)
      },
    }),
    [role],
  )

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>
}

export default AuthProvider
