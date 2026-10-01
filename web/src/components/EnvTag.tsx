import { ENV_LABEL, type EnvType } from './env.ts'
import './EnvTag.css'

// Figma 「02 Core · Env Tag」
function EnvTag({ env }: { env: EnvType }) {
  return (
    <span className="env-tag">
      <span className="env-tag__color" style={{ background: `var(--color-env-${env})` }} aria-hidden="true" />
      {ENV_LABEL[env]}
    </span>
  )
}

export default EnvTag
