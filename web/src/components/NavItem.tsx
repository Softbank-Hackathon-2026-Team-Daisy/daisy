import { NavLink, useLocation } from 'react-router'
import Icon from './Icon.tsx'
import type { IconName } from './icons.ts'
import Tooltip from './Tooltip.tsx'
import './NavItem.css'

// Figma 「08 · Nav Item」. 활성은 surface-strong 배경 + 왼쪽 2px ink 막대 (노란색 안 써요)
type NavItemProps = {
  icon: IconName
  label: string
  collapsed: boolean
} & ({ to: string; activePrefix?: string; end?: boolean } | { onClick: () => void; active?: boolean })

function NavItem(props: NavItemProps) {
  const { icon, label, collapsed } = props
  const { pathname } = useLocation()

  const content = (
    <>
      <Icon name={icon} />
      {!collapsed && <span className="nav-item__label">{label}</span>}
    </>
  )

  const classFor = (active: boolean) =>
    ['nav-item', collapsed && 'nav-item--collapsed', active && 'nav-item--active'].filter(Boolean).join(' ')

  const item =
    'to' in props ? (
      <NavLink
        to={props.to}
        end={props.end}
        aria-label={collapsed ? label : undefined}
        className={({ isActive }) =>
          classFor(isActive || (!!props.activePrefix && pathname.startsWith(props.activePrefix)))
        }
      >
        {content}
      </NavLink>
    ) : (
      <button type="button" className={classFor(!!props.active)} aria-label={collapsed ? label : undefined} onClick={props.onClick}>
        {content}
      </button>
    )

  return collapsed ? <Tooltip text={label}>{item}</Tooltip> : item
}

export default NavItem
