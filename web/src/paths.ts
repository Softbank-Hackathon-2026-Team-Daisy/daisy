// 화면 경로 (SPEC.md §2). 화면 ID ↔ URL을 한곳에서 관리해요. 링크는 문자열 대신 이 함수로 만들어요
export const paths = {
  login: () => '/login', // W-00 · W-00b
  connect: () => '/connect', // W-02 (W-02b 업로드는 범위 제외)
  overview: (p: string) => `/projects/${p}`, // W-01
  build: (p: string) => `/projects/${p}/deploy/build`, // W-03
  targets: (p: string) => `/projects/${p}/deploy/targets`, // W-04
  currentDeployment: (p: string) => `/projects/${p}/deployments/current`, // 사이드바 "배포" → 진행 중인 배포의 현재 단계
  generate: (p: string, d: string) => `/projects/${p}/deployments/${d}/generate`, // W-05 · W-05b
  approve: (p: string, d: string) => `/projects/${p}/deployments/${d}/approve`, // W-06
  progress: (p: string, d: string) => `/projects/${p}/deployments/${d}/progress`, // W-07
  result: (p: string, d: string) => `/projects/${p}/deployments/${d}/result`, // W-08
  history: (p: string) => `/projects/${p}/history`, // W-09
  environments: (p: string) => `/projects/${p}/environments`, // W-10
  scripts: (p: string) => `/projects/${p}/scripts`, // W-11
  aiUsage: (p: string) => `/projects/${p}/ai-usage`, // W-12
  settings: (p: string) => `/projects/${p}/settings`, // W-13
}
