import { useState } from 'react'
import { Navigate, Outlet, useLocation, useParams } from 'react-router'
import { useAuth } from '../api/auth.ts'
import Sidebar from '../components/Sidebar.tsx'
import { MOCK_PROJECTS } from '../mocks/workspace.ts'
import { isFlowPath } from '../paths.ts'
import MacAppDialog from './app-download/MacAppDialog.tsx'
import './AppLayout.css'

// 로그인 뒤 모든 화면의 틀 (로그인 안 했으면 W-00으로): 왼쪽 사이드바 + 오른쪽 화면. W-14 Mac 앱 다운로드는 여기서 Dialog로 띄워요
function AppLayout() {
  const { pathname } = useLocation()
  const { projectId = MOCK_PROJECTS[0].id } = useParams()
  const [userCollapsed, setUserCollapsed] = useState(false)
  const [macAppOpen, setMacAppOpen] = useState(false)
  const flow = isFlowPath(pathname)
  const { role } = useAuth()

  if (!role) return <Navigate to={`/login?next=${encodeURIComponent(pathname)}`} replace />

  return (
    <div className="app-layout">
      <Sidebar
        projectId={projectId}
        collapsed={flow || userCollapsed}
        canToggle={!flow}
        onToggle={() => setUserCollapsed((v) => !v)}
        onOpenMacApp={() => setMacAppOpen(true)}
      />
      <main className="app-layout__main">
        <Outlet />
      </main>
      <MacAppDialog open={macAppOpen} onClose={() => setMacAppOpen(false)} />
    </div>
  )
}

export default AppLayout
