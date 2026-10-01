import { cloneElement, isValidElement, useId, type ReactElement, type ReactNode } from 'react'
import './Tooltip.css'

// Figma 「03 · Tooltip」. 마우스를 올리거나 키보드로 포커스하면 위에 떠요
// 설명(aria-describedby)은 감싼 요소(버튼 등)에 붙여야 스크린리더가 읽어요
type TooltipProps = {
  text: string
  children: ReactNode
}

function Tooltip({ text, children }: TooltipProps) {
  const id = useId()
  return (
    <span className="tooltip">
      {isValidElement(children) ? cloneElement(children as ReactElement<{ 'aria-describedby'?: string }>, { 'aria-describedby': id }) : children}
      <span className="tooltip__bubble" role="tooltip" id={id}>
        {text}
      </span>
    </span>
  )
}

export default Tooltip
