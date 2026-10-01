import { useEffect, useId, useRef, useState, type KeyboardEvent, type ReactNode } from 'react'
import Icon from './Icon.tsx'
import './Select.css'

// Figma 「03 · Select」 + 「Select Menu」. 브랜치 선택처럼 목록에서 하나를 고를 때 써요
export type SelectOption = { value: string; label: string }

type SelectProps = {
  value: string
  options: SelectOption[]
  onChange: (value: string) => void
  label: string
  leading?: ReactNode
  disabled?: boolean
}

function Select({ value, options, onChange, label, leading, disabled }: SelectProps) {
  const [open, setOpen] = useState(false)
  const [active, setActive] = useState(0)
  const rootRef = useRef<HTMLDivElement>(null)
  const listId = useId()
  const current = options.find((o) => o.value === value)

  useEffect(() => {
    if (!open) return
    const onPointerDown = (e: PointerEvent) => {
      if (!rootRef.current?.contains(e.target as Node)) setOpen(false)
    }
    document.addEventListener('pointerdown', onPointerDown)
    return () => document.removeEventListener('pointerdown', onPointerDown)
  }, [open])

  const openMenu = () => {
    setActive(Math.max(0, options.findIndex((o) => o.value === value)))
    setOpen(true)
  }

  const choose = (index: number) => {
    onChange(options[index].value)
    setOpen(false)
  }

  const onKeyDown = (e: KeyboardEvent) => {
    if (!open) {
      if (['ArrowDown', 'ArrowUp', 'Enter', ' '].includes(e.key)) {
        e.preventDefault()
        openMenu()
      }
      return
    }
    if (e.key === 'ArrowDown') setActive((i) => Math.min(options.length - 1, i + 1))
    else if (e.key === 'ArrowUp') setActive((i) => Math.max(0, i - 1))
    else if (e.key === 'Enter' || e.key === ' ') choose(active)
    else if (e.key === 'Escape' || e.key === 'Tab') setOpen(false)
    else return
    if (e.key !== 'Tab') e.preventDefault()
  }

  return (
    <div className="select" ref={rootRef}>
      <button
        type="button"
        className="select__trigger"
        aria-label={label}
        aria-haspopup="listbox"
        aria-expanded={open}
        aria-controls={listId}
        aria-activedescendant={open ? `${listId}-${active}` : undefined}
        disabled={disabled}
        onClick={() => (open ? setOpen(false) : openMenu())}
        onKeyDown={onKeyDown}
      >
        {leading}
        <span className="select__value">{current?.label ?? ''}</span>
        <Icon name="chevron-down" size={16} />
      </button>
      {open && <SelectMenu id={listId} options={options} value={value} active={active} onChoose={choose} />}
    </div>
  )
}

type SelectMenuProps = {
  id: string
  options: SelectOption[]
  value: string
  active: number
  onChoose: (index: number) => void
}

function SelectMenu({ id, options, value, active, onChoose }: SelectMenuProps) {
  return (
    <ul className="select-menu" id={id} role="listbox">
      {options.map((o, i) => (
        <li
          key={o.value}
          id={`${id}-${i}`}
          role="option"
          aria-selected={o.value === value}
          className={['select-menu__option', i === active && 'select-menu__option--active'].filter(Boolean).join(' ')}
          onPointerDown={(e) => e.preventDefault()}
          onClick={() => onChoose(i)}
        >
          <span>{o.label}</span>
          {o.value === value && <Icon name="check" size={16} />}
        </li>
      ))}
    </ul>
  )
}

export default Select
