// 전환 로딩(L-01 ~ L-03) 설명 문구 — 이 파일 한 곳에서만 관리해요 (Figma 「07 · Caption Rotation」)
// 첫 문구는 화면별 고정 문구, 이후 01 → 10 순서로 3.5초마다 반복해요

export const CAPTIONS = [
  'AI가 환경별 인프라 코드를 만들고 있어요',
  'deploy.yaml을 읽고 필요한 리소스를 고르고 있어요',
  'terraform validate로 문법을 확인하고 있어요',
  'terraform plan으로 바뀔 리소스를 계산하고 있어요',
  '보안 그룹이 전체 공개되지 않았는지 살펴보고 있어요',
  '오류가 나면 AI가 로그를 읽고 최대 3번까지 고쳐요',
  '검증된 스크립트가 있으면 이미지 태그만 바꿔 재사용해요',
  '모든 환경에 같은 커밋 해시 이미지가 올라가요',
  '환경마다 state를 따로 보관해서 서로 부딪히지 않아요',
  '인프라는 네트워크부터 한 층씩 쌓여요',
] as const

export type TransitionKind = 'l01' | 'l02' | 'l03'

export const FIRST_CAPTION: Record<TransitionKind, string> = {
  l01: '저장소를 연결하고 있어요',
  l02: CAPTIONS[0],
  l03: '승인된 plan으로 배포를 준비하고 있어요',
}

export const CAPTION_MS = 3500
