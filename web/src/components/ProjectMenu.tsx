import { t } from '../i18n/index.ts'
import Icon from './Icon.tsx'
import './ProjectMenu.css'

// Figma 「08 · Project Menu」. 사이드바 프로젝트 전환 메뉴 (겹치는 요소라 1px ink 테두리)
export type ProjectMenuItem = { id: string; name: string; initials: string; meta: string }

type ProjectMenuProps = {
  projects: ProjectMenuItem[]
  currentId: string
  onSelect: (id: string) => void
  onConnect: () => void
}

function ProjectMenu({ projects, currentId, onSelect, onConnect }: ProjectMenuProps) {
  return (
    <div className="project-menu" role="menu" aria-label={t('프로젝트 전환')}>
      <p className="project-menu__title t-overline t-muted">Projects</p>
      {projects.map((p) => (
        <button
          key={p.id}
          type="button"
          role="menuitemradio"
          aria-checked={p.id === currentId}
          className="project-menu__item"
          onClick={() => onSelect(p.id)}
        >
          <span className="project-initials">{p.initials}</span>
          <span className="project-menu__text">
            <span className="t-label">{p.name}</span>
            <span className="t-mono-sm t-muted">{p.meta}</span>
          </span>
          {p.id === currentId && <Icon name="check" />}
        </button>
      ))}
      <hr className="project-menu__divider" />
      <button type="button" role="menuitem" className="project-menu__item project-menu__connect" onClick={onConnect}>
        <Icon name="plus" />
        <span className="t-label">{t('새 프로젝트 연결')}</span>
      </button>
    </div>
  )
}

export default ProjectMenu
