import { useMemo } from 'react'
import { qrMatrix } from '../utils/qr.ts'

// QR 코드 — 인라인 SVG. 스캐너는 밝은 바탕의 어두운 칸만 잘 읽어서,
// 테마와 상관없이 검정 칸 · 흰 바탕으로 그려요(토큰 예외). 둘레 4칸은 비워 둬요(quiet zone)
type QrCodeProps = { value: string; size?: number; label?: string }

const QUIET = 4

function QrCode({ value, size = 72, label }: QrCodeProps) {
  const { path, dim } = useMemo(() => {
    const m = qrMatrix(value)
    let d = ''
    m.forEach((row, y) =>
      row.forEach((dark, x) => {
        if (dark) d += `M${x + QUIET} ${y + QUIET}h1v1h-1z`
      }),
    )
    return { path: d, dim: m.length + QUIET * 2 }
  }, [value])

  return (
    <svg
      role="img"
      aria-label={label ?? value}
      width={size}
      height={size}
      viewBox={`0 0 ${dim} ${dim}`}
      shapeRendering="crispEdges"
      style={{ display: 'block', flex: 'none', border: '1px solid var(--color-line)', background: '#ffffff' }}
    >
      <rect width={dim} height={dim} fill="#ffffff" />
      <path d={path} fill="#000000" />
    </svg>
  )
}

export default QrCode
