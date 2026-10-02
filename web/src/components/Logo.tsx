import './Logo.css'

// Figma 「02 Core · Logo」 — 꽃잎 8개 + 코어, 워드마크 "unibloom"(소문자, 10/1 서비스 이름 변경). brand는 코어만 노란색이에요
type LogoProps = {
  type?: 'mark' | 'lockup'
  color?: 'ink' | 'brand'
  size?: number
}

const PETALS = [
  'M18.5 1H13.5V9H18.5V1Z',
  'M28.3744 7.16114L24.8389 3.62561L19.182 9.28246L22.7175 12.818L28.3744 7.16114Z',
  'M31 18.5V13.5H23V18.5H31Z',
  'M24.8387 28.3743L28.3743 24.8388L22.7174 19.182L19.1819 22.7175L24.8387 28.3743Z',
  'M13.5 31H18.5V23H13.5V31Z',
  'M3.6256 24.8389L7.16113 28.3744L12.818 22.7175L9.28245 19.182L3.6256 24.8389Z',
  'M1 13.5L1 18.5H9V13.5L1 13.5Z',
  'M7.16127 3.62566L3.62573 7.16119L9.28259 12.818L12.8181 9.28251L7.16127 3.62566Z',
]

function Logo({ type = 'lockup', color = 'brand', size = 32 }: LogoProps) {
  return (
    <span className="logo" role="img" aria-label="Unibloom">
      <svg viewBox="0 0 32 32" width={size} height={size} aria-hidden="true">
        {PETALS.map((d) => (
          <path key={d} d={d} fill="currentColor" />
        ))}
        <path d="M20.5 11.5H11.5V20.5H20.5V11.5Z" fill={color === 'brand' ? 'var(--color-primary)' : 'currentColor'} />
      </svg>
      {type === 'lockup' && <span className="logo__wordmark">unibloom</span>}
    </span>
  )
}

export default Logo
