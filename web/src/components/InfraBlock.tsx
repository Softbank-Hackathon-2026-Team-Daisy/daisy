import './InfraBlock.css'

// Figma 「07 · Infra Block」 172×196. 2.5D 아이소메트릭(2:1), ink 한 색 (윗면 55% · 왼면 82% · 오른면 100%)
// 바닥은 고정이고 그 위에 같은 크기 블록 0~3개. 로딩 애니메이션(L-01 ~ L-03)은 TransitionLoader가 stack을 바꿔요

type Faces = { top: string; left: string; right: string }

// 블록 윗면 중심 y가 c일 때 세 면
function blockFaces(c: number): Faces {
  return {
    top: `M86 ${c - 20}L126 ${c}L86 ${c + 20}L46 ${c}Z`,
    left: `M46 ${c}L86 ${c + 20}V${c + 56}L46 ${c + 36}Z`,
    right: `M126 ${c}L86 ${c + 20}V${c + 56}L126 ${c + 36}Z`,
  }
}

const GROUND: Faces = {
  top: 'M86 96L166 136L86 176L6 136Z',
  left: 'M6 136L86 176V188L6 148Z',
  right: 'M166 136L86 176V188L166 148Z',
}

// 아래부터 1층 · 2층 · 3층
const BLOCKS = [100, 64, 28].map(blockFaces)

function Shape({ faces }: { faces: Faces }) {
  return (
    <>
      {(['left', 'right', 'top'] as const).map((side) => (
        <path key={side} d={faces[side]} className={`infra-block__face infra-block__face--${side}`} />
      ))}
    </>
  )
}

type InfraBlockProps = {
  stack: 0 | 1 | 2 | 3
  // 애니메이션 중이면 새로 쌓이는 블록에 떨어지는 모션을 줘요
  animated?: boolean
}

function InfraBlock({ stack, animated = false }: InfraBlockProps) {
  return (
    <svg className="infra-block" viewBox="0 0 172 196" width="172" height="196" aria-hidden="true">
      <Shape faces={GROUND} />
      {BLOCKS.slice(0, stack).map((faces, i) => (
        <g key={i} className={animated && i === stack - 1 ? 'infra-block__drop' : undefined}>
          <Shape faces={faces} />
        </g>
      ))}
    </svg>
  )
}

export default InfraBlock
