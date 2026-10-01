import { createContext, useContext } from 'react'
import type { AuthToken } from './types.ts'

// 로그인 상태 — 토큰은 client.ts 메모리에 두고, 화면은 역할(role)만 봐요. viewer는 승인 버튼이 비활성이에요
export type AuthState = {
  role: AuthToken['role'] | null
  signIn: (token: AuthToken) => void
  signOut: () => void
}

export const AuthContext = createContext<AuthState>({
  role: null,
  signIn: () => {},
  signOut: () => {},
})

export function useAuth() {
  return useContext(AuthContext)
}
