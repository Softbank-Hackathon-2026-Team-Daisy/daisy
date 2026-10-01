// 환경 종류와 화면 문구 — Env Tag · Env Select Card · 사이드바가 같이 써요
export type EnvType = 'onprem' | 'aws' | 'gcp' | 'azure'

export const ENV_LABEL: Record<EnvType, string> = {
  onprem: '온프레미스',
  aws: 'AWS',
  gcp: 'GCP',
  azure: 'Azure',
}
