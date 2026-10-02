import type { EnvType } from './env.ts'
import { ENV_LABEL } from './env.ts'
import { t } from '../i18n/index.ts'
import CloudLogo from './CloudLogo.tsx'
import Icon from './Icon.tsx'
import './ParityTable.css'

// Figma 「06 · Parity Table」 동일성 검증 — "이식성" 데모 포인트. 값이 기준(첫 성공 환경)과 같으면 ✓, 다르면 ✕
// format: 칸에 보여줄 모양(예: 긴 digest 줄이기). 전체 값은 마우스를 올리면 title로 보여요
export type ParityRow = { label: string; values: Record<string, string | null>; failed?: string[]; format?: (value: string) => string }

type ParityTableProps = {
  envs: { id: string; type: EnvType }[]
  rows: ParityRow[]
  matched: number
  // 이미지가 실제로 다를 때만 주황. 헬스체크 실패처럼 이미지와 상관없는 불일치는 초록 그대로
  mismatch?: boolean
  // 비교할 값(digest)을 하나도 못 받았으면 "n/m 일치" 대신 "확인 전"
  unknown?: boolean
}

function ParityTable({ envs, rows, matched, mismatch, unknown }: ParityTableProps) {
  const all = !(mismatch ?? matched !== envs.length)
  return (
    <section className="parity">
      <header className="parity__title">
        <h2 className="t-h2">{t('동일성 검증')}</h2>
        <span className="t-body-sm t-muted">{t('모든 환경이 같은 상태인지 비교해요')}</span>
        {unknown ? (
          <span className="parity__summary parity__summary--unknown">{t('확인 전')}</span>
        ) : (
          <span className={`parity__summary ${all ? '' : 'parity__summary--partial'}`}>
            <Icon name={all ? 'circle-check' : 'alert-triangle'} size={14} />
            {t('{matched}/{total} 일치', { matched, total: envs.length })}
          </span>
        )}
      </header>
      <table className="parity__table">
        <thead>
          <tr>
            <th scope="col">{t('항목')}</th>
            {envs.map((e) => (
              <th scope="col" key={e.id}>
                {e.type === 'onprem' ? <span className="parity__env" style={{ background: `var(--color-env-${e.type})` }} /> : <CloudLogo env={e.type} size={14} />}
                {t(ENV_LABEL[e.type])}
              </th>
            ))}
          </tr>
        </thead>
        <tbody>
          {rows.map((row) => (
            <tr key={row.label}>
              <th scope="row">{row.label}</th>
              {envs.map((e) => {
                const value = row.values[e.id]
                const bad = row.failed?.includes(e.id)
                return (
                  <td key={e.id} className={bad ? 'parity__bad' : undefined}>
                    {value == null ? (
                      '—'
                    ) : (
                      <>
                        <Icon name={bad ? 'x' : 'check'} size={14} label={bad ? t('다름') : t('같음')} />
                        <span className="t-mono-sm parity__value" title={value}>
                          {row.format ? row.format(value) : value}
                        </span>
                      </>
                    )}
                  </td>
                )
              })}
            </tr>
          ))}
        </tbody>
      </table>
    </section>
  )
}

export default ParityTable
