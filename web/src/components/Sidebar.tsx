import { useEffect, useRef, useState } from 'react'
import { useNavigate } from 'react-router'
import { useAuth } from '../api/auth.ts'
import { avatarName, initials, ROLE_LABEL, useWorkspace } from '../api/useWorkspace.ts'
import { t } from '../i18n/index.ts'
import CloudLogo from './CloudLogo.tsx'
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
  // 768px 이하에서는 화면 위에 겹치는 서랍이에요 (AppLayout이 열고 닫아요). 닫혀 있으면 화면 밖에 숨겨요
  drawer?: 'open' | 'closed'
}

function Sidebar({ projectId, collapsed, canToggle, onToggle, onOpenMacApp, drawer }: SidebarProps) {
  const navigate = useNavigate()
  const [menuOpen, setMenuOpen] = useState(false)
  const switcherRef = useRef<HTMLDivElement>(null)
  // 프로젝트 · 환경 · 사용자는 A-01 · A-02 · R-03 (목업 모드면 목업이 답해요)
  const ws = useWorkspace(projectId)
  const { signOut } = useAuth()
  const name = ws.project?.name ?? t('프로젝트')

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

  const p = projectId

  return (
    <nav
      id="app-sidebar"
      className={['sidebar', collapsed && 'sidebar--collapsed', drawer && 'sidebar--drawer', drawer === 'open' && 'sidebar--open'].filter(Boolean).join(' ')}
      aria-label={t('프로젝트 메뉴')}
      inert={drawer === 'closed' || undefined}
    >
      <Logo type={collapsed ? 'mark' : 'lockup'} color="ink" />

      <div className="sidebar__switcher" ref={switcherRef}>
        <button
          type="button"
          className="sidebar__project"
          aria-haspopup="menu"
          aria-expanded={menuOpen}
          aria-label={t('프로젝트: {name}', { name })}
          onClick={() => setMenuOpen((v) => !v)}
        >
          <span className="project-initials">{initials(name)}</span>
          {!collapsed && (
            <>
              <span className="sidebar__project-text">
                <span className="t-label">{name}</span>
                <span className="t-mono-sm t-muted">{ws.project?.default_branch ?? '—'}</span>
              </span>
              <Icon name="chevron-down" />
            </>
          )}
        </button>
        {menuOpen && (
          <div className="sidebar__menu">
            <ProjectMenu
              projects={ws.projects.map((x) => ({ id: x.id, name: x.name, initials: initials(x.name), meta: x.default_branch ?? '—' }))}
              currentId={projectId}
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
        <Tooltip text={t('새 배포')}>
          <button type="button" className="sidebar__new" aria-label={t('새 배포')} onClick={() => navigate(paths.build(p))}>
            <Icon name="plus" />
          </button>
        </Tooltip>
      ) : (
        <Button variant="outline" className="sidebar__new-wide" onClick={() => navigate(paths.build(p))}>
          {t('새 배포')}
        </Button>
      )}

      <div className="sidebar__group">
        {!collapsed && <p className="t-overline t-muted">Project</p>}
        <NavItem collapsed={collapsed} icon="cloud" label={t('개요')} to={paths.overview(p)} end />
        <NavItem
          collapsed={collapsed}
          icon="play"
          label={t('배포')}
          to={paths.currentDeployment(p)}
          activePrefix={`/projects/${p}/deploy`}
          badge={ws.pendingApprovals || undefined}
        />
        <NavItem collapsed={collapsed} icon="server" label={t('환경')} to={paths.environments(p)} />
        <NavItem collapsed={collapsed} icon="clock" label={t('이력')} to={paths.history(p)} />
        <NavItem collapsed={collapsed} icon="terminal" label={t('스크립트')} to={paths.scripts(p)} />
      </div>

      <div className="sidebar__envs">
        {collapsed ? (
          ws.envsMocked && <MockBadge compact />
        ) : (
          <p className="sidebar__envs-title t-overline t-muted">
            Environments {ws.envsMocked && <MockBadge />}
          </p>
        )}
        {ws.envs.map((env) =>
          collapsed ? (
            <span key={env.targetId} className="sidebar__env-dots" aria-label={`${t(ENV_LABEL[env.type])} · ${env.label}`} role="img">
              <span className="sidebar__env-color" style={{ background: `var(--color-env-${env.type})` }} />
              <span className="sidebar__status-dot" style={{ background: `var(--color-status-${env.tone})` }} />
            </span>
          ) : (
            <button key={env.targetId} type="button" className="sidebar__env" onClick={() => navigate(paths.environments(p))}>
              {env.type === 'onprem' ? <span className="sidebar__env-color" style={{ background: `var(--color-env-${env.type})` }} /> : <CloudLogo env={env.type} size={14} />}
              <span className="sidebar__env-name">{t(ENV_LABEL[env.type])}</span>
              <span className="sidebar__status-dot" style={{ background: `var(--color-status-${env.tone})` }} />
              <span className="t-mono-sm t-muted">{env.label}</span>
            </button>
          ),
        )}
      </div>

      <div className="sidebar__spacer" />

      <div className="sidebar__group">
        <NavItem collapsed={collapsed} icon="download" label={t('Mac 앱 받기')} onClick={onOpenMacApp} />
        <NavItem collapsed={collapsed} icon="signal" label={t('AI 사용량')} to={paths.aiUsage(p)} />
        <NavItem collapsed={collapsed} icon="settings" label={t('설정')} to={paths.settings(p)} />
      </div>

      <hr className="sidebar__divider" />
      {/* 프로젝트 채널(SSE) 상태 — 목업 · 서버 채널이 없으면 "5초마다 새로고침" */}
      <ConnectionIndicator state={ws.live} compact={collapsed} />

      <div className="sidebar__user">
        {/* 한글 이름은 Figma처럼 성을 뺀 첫 글자 */}
        <Avatar type="human" name={avatarName(ws.user?.username)} size="m" />
        {!collapsed && (
          <span className="sidebar__user-text">
            <span className="t-label">{ws.user?.username ?? '—'}</span>
            <span className="t-mono-sm t-muted">{ws.user ? t(ROLE_LABEL[ws.user.role]) : ''}</span>
          </span>
        )}
        {/* 로그아웃 — 계정을 바꾸려면 탭을 닫지 않아도 돼요 (앱과 같아요) */}
        <button type="button" className="sidebar__toggle" aria-label={t('로그아웃')} title={t('로그아웃')} onClick={signOut}>
          <Icon name="log-out" />
        </button>
        {canToggle && (
          <button
            type="button"
            className={['sidebar__toggle', !collapsed && 'sidebar__toggle--open'].filter(Boolean).join(' ')}
            aria-label={collapsed ? t('사이드바 펼치기') : t('사이드바 접기')}
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
