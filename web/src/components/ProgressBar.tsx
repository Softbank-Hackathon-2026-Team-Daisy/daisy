import './ProgressBar.css'

// Figma 「03 · Progress Bar」. value는 0~100
type ProgressBarProps = {
  value: number
  label: string
}

function ProgressBar({ value, label }: ProgressBarProps) {
  const pct = Math.round(Math.min(100, Math.max(0, value)))
  return (
    <div className="progress">
      <div className="progress__head">
        <span className="t-label">{label}</span>
        <span className="t-mono-sm t-muted">{pct}%</span>
      </div>
      <div className="progress__track" role="progressbar" aria-label={label} aria-valuenow={pct} aria-valuemin={0} aria-valuemax={100}>
        <div className="progress__bar" style={{ width: `${pct}%` }} />
      </div>
    </div>
  )
}

export default ProgressBar
