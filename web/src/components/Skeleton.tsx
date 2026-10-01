import './Skeleton.css'

// Figma 「03 · Skeleton」. 데이터를 불러오는 동안 자리만 잡아요
type SkeletonProps = {
  shape?: 'line' | 'block' | 'circle'
  width?: number | string
  height?: number | string
}

function Skeleton({ shape = 'line', width, height }: SkeletonProps) {
  return <span className={`skeleton skeleton--${shape}`} style={{ width, height }} aria-hidden="true" />
}

export default Skeleton
