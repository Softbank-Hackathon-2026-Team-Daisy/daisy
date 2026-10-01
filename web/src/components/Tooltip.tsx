import { useId, type ReactNode } from 'react'
import './Tooltip.css'

// Figma 「03 · Tooltip」. 마우스를 올리거나 키보드로 포커스하면 위에 떠요
type TooltipProps = {
  text: string
  children: ReactNode
}

function Tooltip({ text, children }: TooltipProps) {
  const id = useId()
  return (
    <span className="tooltip" aria-describedby={id}>
      {children}
      <span className="tooltip__bubble" role="tooltip" id={id}>
        {text}
      </span>
    </span>
  )
}

export default Tooltip
