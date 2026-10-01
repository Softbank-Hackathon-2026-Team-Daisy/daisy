import { useEffect, useRef, useState } from 'react'
import { useNavigate } from 'react-router'
import { MOCK_ENVS, MOCK_PENDING_APPROVALS, MOCK_PROJECTS, MOCK_USER } from '../mocks/workspace.ts'
import { paths } from '../paths.ts'
import Avatar from './Avatar.tsx'
import Button from './Button.tsx'
import ConnectionIndicator from './ConnectionIndicator.tsx'
import { ENV_LABEL } from './env.ts'
import Icon from './Icon.tsx'
import Logo from './Logo.tsx'
import MockBadge from './MockBadge.tsx'
import NavItem from './NavItem.tsx'
import ProjectMenu from './ProjectMenu.tsx'
import Tooltip from './Tooltip.tsx'
import './Sidebar.css'

// Figma 「08 · Sidebar」. 펼침 240px / 접힘 64px (배포 흐름 화면은 항상 접힘, SPEC.md §2-4)
type SidebarProps = {
  projectId: string
  collapsed: boolean
  canToggle: boolean
  onToggle: () => void
  onOpenMacApp: () => void
}

function Sidebar({ projectId, collapsed, canToggle, onToggle, onOpenMacApp }: SidebarProps) {
  const navigate = useNavigate()
  const [menuOpen, setMenuOpen] = useState(false)
  const switcherRef = useRef<HTMLDivElement>(null)
  // MOCK: 프로젝트 · 환경 · 사용자는 서버 연결 전까지 목업
  const project = MOCK_PROJECTS.find((p) => p.id === projectId) ?? MOCK_PROJECTS[0]

  useEffect(() => {
    if (!menuOpen) return
    const close = (e: PointerEvent | KeyboardEvent) => {
      if (e instanceof KeyboardEvent ? e.key === 'Escape' : !switcherRef.current?.contains(e.target as Node)) setMenuOpen(false)
    }
    document.addEventListener('pointerdown', close)
    document.addEventListener('keydown', close)
    return () => {
      document.removeEventListener('pointerdown', close)
      document.removeEventListener('keydown', close)
    }
  }, [menuOpen])

  const p = project.id

  return (
    <nav className={['sidebar', collapsed && 'sidebar--collapsed'].filter(Boolean).join(' ')} aria-label="프로젝트 메뉴">
      <Logo type={collapsed ? 'mark' : 'lockup'} color="ink" />

      <div className="sidebar__switcher" ref={switcherRef}>
        <button
          type="button"
          className="sidebar__project"
          aria-haspopup="menu"
          aria-expanded={menuOpen}
          aria-label={`프로젝트: ${project.name}`}
          onClick={() => setMenuOpen((v) => !v)}
        >
          <span className="project-initials">{project.initials}</span>
          {!collapsed && (
            <>
              <span className="sidebar__project-text">
                <span className="t-label">{project.name}</span>
                <span className="t-mono-sm t-muted">
                  {project.branch} · {project.commit}
                </span>
              </span>
              <Icon name="chevron-down" />
            </>
          )}
        </button>
        {menuOpen && (
          <div className="sidebar__menu">
            <ProjectMenu
              projects={MOCK_PROJECTS.map((x) => ({ id: x.id, name: x.name, initials: x.initials, meta: `${x.branch} · ${x.summary}` }))}
              currentId={project.id}
              onSelect={(id) => {
                setMenuOpen(false)
                navigate(paths.overview(id))
              }}
              onConnect={() => {
                setMenuOpen(false)
                navigate(paths.connect())
              }}
            />
          </div>
        )}
      </div>

      {collapsed ? (
        <Tooltip text="새 배포">
          <button type="button" className="sidebar__new" aria-label="새 배포" onClick={() => navigate(paths.build(p))}>
            <Icon name="plus" />
          </button>
        </Tooltip>
      ) : (
        <Button variant="outline" className="sidebar__new-wide" onClick={() => navigate(paths.build(p))}>
          새 배포
        </Button>
      )}

      <div className="sidebar__group">
        {!collapsed && <p className="t-overline t-muted">Project</p>}
        <NavItem collapsed={collapsed} icon="cloud" label="개요" to={paths.overview(p)} end />
        <NavItem
          collapsed={collapsed}
          icon="play"
          label="배포"
          to={paths.currentDeployment(p)}
          activePrefix={`/projects/${p}/deploy`}
          badge={MOCK_PENDING_APPROVALS}
        />
        <NavItem collapsed={collapsed} icon="server" label="환경" to={paths.environments(p)} />
        <NavItem collapsed={collapsed} icon="clock" label="이력" to={paths.history(p)} />
        <NavItem collapsed={collapsed} icon="terminal" label="스크립트" to={paths.scripts(p)} />
      </div>

      <div className="sidebar__envs">
        {!collapsed && (
          <p className="sidebar__envs-title t-overline t-muted">
            Environments <MockBadge />
          </p>
        )}
        {MOCK_ENVS.map((env) =>
          collapsed ? (
            <span key={env.type} className="sidebar__env-dots" aria-label={`${ENV_LABEL[env.type]} · ${env.statusLabel}`} role="img">
              <span className="sidebar__env-color" style={{ background: `var(--color-env-${env.type})` }} />
              <span className="sidebar__status-dot" style={{ background: `var(--color-status-${env.status})` }} />
            </span>
          ) : (
            <button key={env.type} type="button" className="sidebar__env" onClick={() => navigate(paths.environments(p))}>
              <span className="sidebar__env-color" style={{ background: `var(--color-env-${env.type})` }} />
              <span className="sidebar__env-name">{ENV_LABEL[env.type]}</span>
              <span className="sidebar__status-dot" style={{ background: `var(--color-status-${env.status})` }} />
              <span className="t-mono-sm t-muted">{env.statusLabel}</span>
            </button>
          ),
        )}
      </div>

      <div className="sidebar__spacer" />

      <div className="sidebar__group">
        <NavItem collapsed={collapsed} icon="download" label="Mac 앱 받기" onClick={onOpenMacApp} />
        <NavItem collapsed={collapsed} icon="signal" label="AI 사용량" to={paths.aiUsage(p)} />
        <NavItem collapsed={collapsed} icon="settings" label="설정" to={paths.settings(p)} />
      </div>

      <hr className="sidebar__divider" />
      {/* MOCK: SSE 연결 상태는 api/realtime을 붙이면 실제 값으로 바꿔요 */}
      <ConnectionIndicator state="connected" compact={collapsed} />

      <div className="sidebar__user">
        {/* Figma처럼 성을 뺀 이름 첫 글자 */}
        <Avatar type="human" name={MOCK_USER.name.slice(1)} size="m" />
        {!collapsed && (
          <span className="sidebar__user-text">
            <span className="t-label">{MOCK_USER.name}</span>
            <span className="t-mono-sm t-muted">{MOCK_USER.role}</span>
          </span>
        )}
        {canToggle && (
          <button
            type="button"
            className={['sidebar__toggle', !collapsed && 'sidebar__toggle--open'].filter(Boolean).join(' ')}
            aria-label={collapsed ? '사이드바 펼치기' : '사이드바 접기'}
            onClick={onToggle}
          >
            <Icon name="chevron-right" />
          </button>
        )}
      </div>
    </nav>
  )
}

export default Sidebar
