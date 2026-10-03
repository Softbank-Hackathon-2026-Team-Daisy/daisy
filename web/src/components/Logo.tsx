import { useId } from 'react'
import './Logo.css'

// 10/3 새 로고 — 파란 그라디언트 위 흰 꽃잎 10장 + 노란 코어, 점선 고리와 작은 점 4개. 워드마크 "unibloom"(소문자)
// 원본 400×400 PNG를 그대로 따라 그렸어요 (public/favicon.svg와 같은 그림)
type LogoProps = {
  type?: 'mark' | 'lockup'
  size?: number
}

const PETAL_ANGLES = [0, 36, 72, 108, 144, 180, 216, 252, 288, 324]
const DOTS = [
  { cx: 276, cy: 68, r: 7, fill: '#ffd23f' },
  { cx: 83, cy: 101, r: 4.5, fill: '#f9a8d4' },
  { cx: 83, cy: 297, r: 5.5, fill: '#a7f3d0' },
  { cx: 332, cy: 276, r: 5.5, fill: '#7dd3fc' },
]

function Logo({ type = 'lockup', size = 32 }: LogoProps) {
  // 한 화면에 로고가 여러 개여도 그라디언트 id가 겹치지 않게
  const gradient = `logo-bg-${useId()}`
  return (
    <span className="logo" role="img" aria-label="Unibloom">
      <svg viewBox="0 0 400 400" width={size} height={size} aria-hidden="true">
        <defs>
          <linearGradient id={gradient} x1="0" y1="0" x2="1" y2="1">
            <stop offset="0" stopColor="#4e46e5" />
            <stop offset="1" stopColor="#0ea4e9" />
          </linearGradient>
        </defs>
        <rect width="400" height="400" rx="88" fill={`url(#${gradient})`} />
        <circle cx="200" cy="200" r="152.5" fill="none" stroke="#fff" strokeOpacity="0.4" strokeWidth="2" strokeLinecap="round" strokeDasharray="0 8" />
        {PETAL_ANGLES.map((a) => (
          <ellipse key={a} cx="200" cy="131" rx="23" ry="62" fill="none" stroke="#fff" strokeWidth="11" transform={`rotate(${a} 200 200)`} />
        ))}
        <circle cx="200" cy="200" r="37" fill="#ffd23f" />
        {DOTS.map((d) => (
          <circle key={d.fill} {...d} />
        ))}
      </svg>
      {type === 'lockup' && <span className="logo__wordmark">unibloom</span>}
    </span>
  )
}

export default Logo
