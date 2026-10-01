import { useEffect, useMemo, useState, type ReactNode } from 'react'
import { useLocation, useNavigate } from 'react-router'
import { AuthContext, type AuthState } from './auth.ts'
import { setAccessToken, setUnauthorizedHandler } from './client.ts'
import type { AuthToken } from './types.ts'

// 로그인 상태를 앱 전체에 나눠요. 401이 오면 토큰을 지우고 로그인 화면(세션 만료 안내)으로 보내요
function AuthProvider({ children }: { children: ReactNode }) {
  const [role, setRole] = useState<AuthToken['role'] | null>(null)
  const navigate = useNavigate()
  const { pathname } = useLocation()

  useEffect(() => {
    setUnauthorizedHandler(() => {
      setAccessToken(null)
      setRole(null)
      navigate(`/login?expired=1&next=${encodeURIComponent(pathname)}`, { replace: true })
    })
  }, [navigate, pathname])

  const value = useMemo<AuthState>(
    () => ({
      role,
      signIn: (token) => {
        setAccessToken(token.access_token)
        setRole(token.role)
      },
      signOut: () => {
        setAccessToken(null)
        setRole(null)
      },
    }),
    [role],
  )

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>
}

export default AuthProvider
