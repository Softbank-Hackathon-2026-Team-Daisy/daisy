import { t } from '../i18n/index.ts'
import CloudLogo from './CloudLogo.tsx'
import { ENV_LABEL, type EnvType } from './env.ts'
import StatusBadge, { type StatusTone } from './StatusBadge.tsx'
import StepItem, { type StepItemState } from './StepItem.tsx'

// Figma 「05 · Deploy Lane」. W-07 환경별 apply 레인 — 위에 환경 색 막대 4px
// onSelect를 주면 레인을 눌러 그 환경 로그를 볼 수 있어요. 키보드는 제목 버튼으로 (선택되면 2px focus 테두리)
type DeployLaneProps = {
  env: EnvType
  region: string
  tone: StatusTone
  label: string
  steps: { label: string; state: StepItemState; duration?: string }[]
  selected?: boolean
  onSelect?: () => void
}

function DeployLane({ env, region, tone, label, steps, selected = false, onSelect }: DeployLaneProps) {
  const envLabel = t(ENV_LABEL[env])
  return (
    <section
      aria-label={t('{env} 배포', { env: envLabel })}
      onClick={onSelect}
      style={{
        display: 'flex',
        flexDirection: 'column',
        gap: 'var(--space-3)',
        // 선택 테두리가 2px라도 안쪽이 움직이지 않게 padding을 1px 줄여요
        padding: selected ? 'calc(var(--space-4) - 1px)' : 'var(--space-4)',
        border: selected ? 'var(--border-focus)' : 'var(--border)',
        borderRadius: 'var(--radius-md)',
        background: 'var(--color-card)',
        cursor: onSelect ? 'pointer' : undefined,
      }}
    >
      <span style={{ height: 4, borderRadius: 'var(--radius-sm)', background: `var(--color-env-${env})` }} />
      <header style={{ display: 'flex', alignItems: 'center', gap: 'var(--space-2)' }}>
        <div style={{ display: 'flex', flex: 1, flexDirection: 'column', gap: 'var(--space-1)' }}>
          <h2 className="t-h2" style={{ display: 'flex', alignItems: 'center', gap: 'var(--space-2)' }}>
            {env !== 'onprem' && <CloudLogo env={env} size={18} />}
            {onSelect ? (
              <button
                type="button"
                aria-pressed={selected}
                title={t('{env} 로그 보기', { env: envLabel })}
                style={{ padding: 0, border: 0, background: 'transparent', color: 'inherit', font: 'inherit', cursor: 'pointer' }}
              >
                {envLabel}
              </button>
            ) : (
              envLabel
            )}
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
