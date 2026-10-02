import { t } from '../i18n/index.ts'
import './Spinner.css'

// Figma 「03 · Spinner」 20px 링. 3초 안에 끝나는 짧은 대기에 써요 (긴 전환은 L-xx 인프라 블록)
function Spinner({ label }: { label?: string }) {
  return (
    <svg className="spinner" viewBox="0 0 20 20" width="20" height="20" role="status" aria-label={label ?? t('불러오는 중')}>
      <circle cx="10" cy="10" r="8.6" fill="none" stroke="var(--color-surface)" strokeWidth="2.8" />
      <path d="M10 1.4A8.6 8.6 0 0 1 7.34 18.18" fill="none" stroke="var(--color-ink)" strokeWidth="2.8" />
    </svg>
  )
}

export default Spinner
