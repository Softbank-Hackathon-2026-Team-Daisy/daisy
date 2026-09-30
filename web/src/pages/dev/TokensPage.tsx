import { useState } from 'react'
import './dev.css'

// 개발용 확인 페이지 (/dev/tokens) — Figma 「01 Foundations」와 눈으로 비교해요. 데모 화면이 아니에요.

const COLORS = [
  'bg', 'surface', 'surface-strong', 'line', 'ink', 'ink-muted', 'primary',
  'on-primary', 'focus', 'success', 'danger', 'warning', 'running', 'rolledback',
  'env-onprem', 'env-aws', 'env-gcp', 'env-azure',
]

const TYPE_SCALE = [
  ['display', '40/48 SemiBold', '환경만 고르면, 모든 클라우드에 배포'],
  ['h1', '24/32 SemiBold', '환경만 고르면, 모든 클라우드에 배포'],
  ['h2', '18/26 SemiBold', '환경만 고르면, 모든 클라우드에 배포'],
  ['body', '15/22 Regular', 'AI가 환경별 Terraform을 만들고 검증해요'],
  ['body-sm', '13/20 Regular', 'AI가 환경별 Terraform을 만들고 검증해요'],
  ['label', '13/18 Medium', '승인하고 배포'],
  ['mono', '13/20 Regular', 'sha256:9f3c…e1a  terraform plan  +12 ~2 −0'],
  ['mono-sm', '12/18 Regular', '10:12:04 gcp WARN revision not ready'],
  ['overline', '11/16 Medium', 'deploy · plan · apply'],
]

const SPACES = [1, 2, 3, 4, 6, 8, 12, 16]
const RADII = [['none', '0 · 기본'], ['sm', '2 · 배지 · 태그'], ['md', '4 · 버튼 · 카드']]

type Theme = 'system' | 'light' | 'dark'

function TokensPage() {
  const [theme, setTheme] = useState<Theme>('system')

  const applyTheme = (next: Theme) => {
    setTheme(next)
    if (next === 'system') document.documentElement.removeAttribute('data-theme')
    else document.documentElement.setAttribute('data-theme', next)
  }

  return (
    <main className="dev-page">
      <header className="dev-header">
        <h1 className="t-h1">Daisy DS · Tokens</h1>
        <div className="dev-theme">
          {(['system', 'light', 'dark'] as const).map((t) => (
            <button key={t} type="button" aria-pressed={theme === t} onClick={() => applyTheme(t)}>
              {t}
            </button>
          ))}
        </div>
      </header>

      <section>
        <p className="t-overline t-muted">Color</p>
        <div className="dev-swatches">
          {COLORS.map((name) => (
            <div key={name}>
              <div className="dev-swatch" style={{ background: `var(--color-${name})` }} />
              <code className="t-mono-sm">--color-{name}</code>
            </div>
          ))}
        </div>
      </section>

      <section>
        <p className="t-overline t-muted">Type · IBM Plex Sans KR / IBM Plex Mono</p>
        {TYPE_SCALE.map(([name, spec, sample]) => (
          <div key={name} className="dev-type-row">
            <span className="t-mono-sm t-muted">{name} {spec}</span>
            <span className={`t-${name}`}>{sample}</span>
          </div>
        ))}
      </section>

      <section className="dev-row">
        <div>
          <p className="t-overline t-muted">Spacing · base 4</p>
          {SPACES.map((n) => (
            <div key={n} className="dev-space">
              <span style={{ width: `var(--space-${n})` }} />
              <code className="t-mono-sm">--space-{n}</code>
            </div>
          ))}
        </div>
        <div>
          <p className="t-overline t-muted">Radius · 0 / 2 / 4</p>
          <div className="dev-radii">
            {RADII.map(([name, label]) => (
              <div key={name}>
                <div className="dev-radius" style={{ borderRadius: `var(--radius-${name})` }} />
                <span className="t-body-sm">{label}</span>
              </div>
            ))}
          </div>
        </div>
      </section>
    </main>
  )
}

export default TokensPage
