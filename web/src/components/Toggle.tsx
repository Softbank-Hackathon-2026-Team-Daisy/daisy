import './Toggle.css'

// Figma 「03 · Toggle」 36×20. 스위치 역할(role="switch")이라 스크린리더가 켜짐/꺼짐으로 읽어요
type ToggleProps = {
  checked: boolean
  onChange: (checked: boolean) => void
  label: string
  disabled?: boolean
}

function Toggle({ checked, onChange, label, disabled }: ToggleProps) {
  return (
    <button
      type="button"
      role="switch"
      aria-checked={checked}
      aria-label={label}
      disabled={disabled}
      className="toggle"
      onClick={() => onChange(!checked)}
    >
      <span className="toggle__knob" />
    </button>
  )
}

export default Toggle
