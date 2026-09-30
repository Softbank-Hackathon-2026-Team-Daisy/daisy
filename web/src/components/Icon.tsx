import { ICON_PATHS, type IconName } from './icons.ts'

// Figma 「03 · Icons」. 색은 부모 글자색(currentColor)을 따라가요. 기본 20px, 버튼 · 입력 안 16px, 표 · 칩 안 14px
type IconProps = {
  name: IconName
  size?: 14 | 16 | 20
  // 뜻이 있는 아이콘만 label을 줘요. 없으면 장식으로 숨겨요
  label?: string
}

function Icon({ name, size = 20, label }: IconProps) {
  return (
    <svg
      viewBox="0 0 20 20"
      width={size}
      height={size}
      fill="none"
      stroke="currentColor"
      strokeWidth={1.5}
      strokeLinecap="square"
      role={label ? 'img' : undefined}
      aria-label={label}
      aria-hidden={label ? undefined : true}
      style={{ flex: 'none' }}
    >
      {ICON_PATHS[name].map((d) => (
        <path key={d} d={d} />
      ))}
    </svg>
  )
}

export default Icon
