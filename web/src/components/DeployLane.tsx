import { t } from '../i18n/index.ts'
import CloudLogo from './CloudLogo.tsx'
import { ENV_LABEL, type EnvType } from './env.ts'
import StatusBadge, { type StatusTone } from './StatusBadge.tsx'
import StepItem, { type StepItemState } from './StepItem.tsx'

// Figma 「05 · Deploy Lane」. W-07 환경별 apply 레인 — 위에 환경 색 막대 4px
type DeployLaneProps = {
  env: EnvType
  region: string
  tone: StatusTone
  label: string
  steps: { label: string; state: StepItemState; duration?: string }[]
}

function DeployLane({ env, region, tone, label, steps }: DeployLaneProps) {
  return (
    <section
      aria-label={t('{env} 배포', { env: t(ENV_LABEL[env]) })}
      style={{
        display: 'flex',
        flexDirection: 'column',
        gap: 'var(--space-3)',
        padding: 'var(--space-4)',
        border: 'var(--border)',
        borderRadius: 'var(--radius-md)',
        background: 'var(--color-card)',
      }}
    >
      <span style={{ height: 4, borderRadius: 'var(--radius-sm)', background: `var(--color-env-${env})` }} />
      <header style={{ display: 'flex', alignItems: 'center', gap: 'var(--space-2)' }}>
        <div style={{ display: 'flex', flex: 1, flexDirection: 'column', gap: 'var(--space-1)' }}>
          <h2 className="t-h2" style={{ display: 'flex', alignItems: 'center', gap: 'var(--space-2)' }}>
            {env !== 'onprem' && <CloudLogo env={env} size={18} />}
            {t(ENV_LABEL[env])}
          </h2>
          <p className="t-body-sm t-muted">{region}</p>
        </div>
        <StatusBadge tone={tone}>{label}</StatusBadge>
      </header>
      <div style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-1)' }}>
        {steps.map((s) => (
          <StepItem key={s.label} state={s.state} label={s.label} duration={s.duration} />
        ))}
      </div>
    </section>
  )
}

export default DeployLane
