import { useMemo, useState } from 'react'
import { Navigate, Outlet, useLocation, useParams } from 'react-router'
import { useAuth } from '../api/auth.ts'
import { events } from '../api/endpoints.ts'
import { ProjectLiveContext } from '../api/projectLive.ts'
import { useRealtime } from '../api/useRealtime.ts'
import Sidebar from '../components/Sidebar.tsx'
import { isFlowPath } from '../paths.ts'
import MacAppDialog from './app-download/MacAppDialog.tsx'
import './AppLayout.css'

// 로그인 뒤 모든 화면의 틀 (로그인 안 했으면 W-00으로): 왼쪽 사이드바 + 오른쪽 화면. W-14 Mac 앱 다운로드는 여기서 Dialog로 띄워요
function AppLayout() {
  const { pathname } = useLocation()
  const { projectId = '' } = useParams()
  const [userCollapsed, setUserCollapsed] = useState(false)
  const [macAppOpen, setMacAppOpen] = useState(false)
  const flow = isFlowPath(pathname)
  const { role } = useAuth()
  // 프로젝트 채널 하나를 여기서 붙여요 (로그인 뒤에만)
  const [tick, setTick] = useState(0)
  const live = useRealtime(role && projectId ? events.project(projectId) : null, { onChange: () => setTick((t) => t + 1) })
  const liveValue = useMemo(() => ({ state: live, tick }), [live, tick])

  if (!role) return <Navigate to={`/login?next=${encodeURIComponent(pathname)}`} replace />

  return (
    <ProjectLiveContext.Provider value={liveValue}>
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
    </ProjectLiveContext.Provider>
  )
}

export default AppLayout
