import { useEffect, useMemo, useState, useSyncExternalStore } from 'react'
import { Navigate, Outlet, useLocation, useParams } from 'react-router'
import { useAuth } from '../api/auth.ts'
import { api, events } from '../api/endpoints.ts'
import { ProjectLiveContext } from '../api/projectLive.ts'
import { useRealtime } from '../api/useRealtime.ts'
import { useResource } from '../api/useResource.ts'
import Logo from '../components/Logo.tsx'
import Sidebar from '../components/Sidebar.tsx'
import { t } from '../i18n/index.ts'
import MacAppDialog from './app-download/MacAppDialog.tsx'
import './AppLayout.css'

// 768px 이하(폰 · 태블릿)에서는 사이드바를 서랍으로 바꾸고 위에 얇은 바를 둬요 (#102)
const NARROW = '(max-width: 768px)'
const subscribeNarrow = (cb: () => void) => {
  const mq = window.matchMedia(NARROW)
  mq.addEventListener('change', cb)
  return () => mq.removeEventListener('change', cb)
}
const getNarrow = () => window.matchMedia(NARROW).matches

// 로그인 뒤 모든 화면의 틀 (로그인 안 했으면 W-00으로): 왼쪽 사이드바 + 오른쪽 화면. W-14 Mac 앱 다운로드는 여기서 Dialog로 띄워요
function AppLayout() {
  const { pathname } = useLocation()
  const { projectId = '' } = useParams()
  const [userCollapsed, setUserCollapsed] = useState(false)
  const [macAppOpen, setMacAppOpen] = useState(false)
  const narrow = useSyncExternalStore(subscribeNarrow, getNarrow, () => false)
  const [drawerOpen, setDrawerOpen] = useState(false)
  // 화면을 옮기면 서랍을 닫아요 (렌더 중에 이전 경로와 비교 — effect 안 setState 대신)
  const [drawerPath, setDrawerPath] = useState(pathname)
  if (drawerPath !== pathname) {
    setDrawerPath(pathname)
    setDrawerOpen(false)
  }
  const drawer = narrow && drawerOpen
  useEffect(() => {
    if (!drawer) return
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') setDrawerOpen(false)
    }
    document.addEventListener('keydown', onKey)
    return () => document.removeEventListener('keydown', onKey)
  }, [drawer])
  const { role } = useAuth()
  // 프로젝트 채널 하나를 여기서 붙여요 (로그인 뒤에만). A-12 last_seq가 있으면 그 지점부터 — 처음부터 전부 다시 받지 않게
  const [tick, setTick] = useState(0)
  const detail = useResource(() => (role && projectId ? api.getProject(projectId) : Promise.resolve(null)), [role, projectId])
  // 프로젝트를 바꾸면 그 프로젝트의 A-12가 올 때까지 기다려요 (앞 프로젝트의 last_seq로 붙지 않게)
  const current = detail.data?.id === projectId ? detail.data : null
  const detailSettled = !!current || (!detail.loading && !!detail.error)
  const live = useRealtime(role && projectId && detailSettled ? events.project(projectId) : null, {
    since: current?.last_seq ?? null,
    onChange: () => setTick((t) => t + 1),
  })
  const liveValue = useMemo(() => ({ state: live, tick }), [live, tick])

  if (!role) return <Navigate to={`/login?next=${encodeURIComponent(pathname)}`} replace />

  return (
    <ProjectLiveContext.Provider value={liveValue}>
    <div className="app-layout">
      {narrow && (
        <header className="app-layout__topbar">
          <Logo type="mark" color="ink" size={24} />
          <span className="app-layout__project t-label">{current?.name ?? t('프로젝트')}</span>
          <button
            type="button"
            className="app-layout__menu"
            aria-label={t('메뉴 열기')}
            aria-expanded={drawerOpen}
            aria-controls="app-sidebar"
            onClick={() => setDrawerOpen((v) => !v)}
          >
            <svg viewBox="0 0 20 20" width={20} height={20} fill="none" stroke="currentColor" strokeWidth={1.5} aria-hidden="true">
              <path d="M3 5.5h14M3 10h14M3 14.5h14" />
            </svg>
          </button>
        </header>
      )}
      {drawer && <div className="app-layout__scrim" aria-hidden="true" onClick={() => setDrawerOpen(false)} />}
      <Sidebar
        projectId={projectId}
        collapsed={!narrow && userCollapsed}
        canToggle={!narrow}
        onToggle={() => setUserCollapsed((v) => !v)}
        onOpenMacApp={() => {
          setDrawerOpen(false)
          setMacAppOpen(true)
        }}
        drawer={narrow ? (drawerOpen ? 'open' : 'closed') : undefined}
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
