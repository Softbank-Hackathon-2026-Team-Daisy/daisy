import './Avatar.css'

// Figma 「03 · Avatar」. 사람은 이름 첫 글자, AI는 "AI" (원형은 상태 점과 아바타만 써요)
type AvatarProps = {
  size?: 's' | 'm'
} & ({ type: 'human'; name: string } | { type: 'ai' })

function Avatar(props: AvatarProps) {
  const { size = 's' } = props
  const isAi = props.type === 'ai'
  return (
    <span
      className={`avatar avatar--${size} avatar--${props.type}`}
      role="img"
      aria-label={isAi ? 'AI' : props.name}
    >
      {isAi ? 'AI' : props.name.slice(0, 1)}
    </span>
  )
}

export default Avatar
