import { t } from '../i18n/index.ts'
import CloudLogo from './CloudLogo.tsx'
import { ENV_LABEL, type EnvType } from './env.ts'
import './EnvTag.css'

// Figma 「02 Core · Env Tag」 — 클라우드는 로고, 온프레미스는 색 점 (10/2)
function EnvTag({ env }: { env: EnvType }) {
  return (
    <span className="env-tag">
      {env === 'onprem' ? <span className="env-tag__color" style={{ background: `var(--color-env-${env})` }} aria-hidden="true" /> : <CloudLogo env={env} />}
      {t(ENV_LABEL[env])}
    </span>
  )
}

export default EnvTag
