import type { EnvType } from './env.ts'
import { ENV_LABEL } from './env.ts'
import Icon from './Icon.tsx'
import './ParityTable.css'

// Figma 「06 · Parity Table」 동일성 검증 — "이식성" 데모 포인트. 값이 기준(첫 성공 환경)과 같으면 ✓, 다르면 ✕
export type ParityRow = { label: string; values: Record<string, string | null>; failed?: string[] }

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
        <h2 className="t-h2">동일성 검증</h2>
        <span className="t-body-sm t-muted">모든 환경이 같은 상태인지 비교해요</span>
        {unknown ? (
          <span className="parity__summary parity__summary--unknown">확인 전</span>
        ) : (
          <span className={`parity__summary ${all ? '' : 'parity__summary--partial'}`}>
            <Icon name={all ? 'circle-check' : 'alert-triangle'} size={14} />
            {matched}/{envs.length} 일치
          </span>
        )}
      </header>
      <table className="parity__table">
        <thead>
          <tr>
            <th scope="col">항목</th>
            {envs.map((e) => (
              <th scope="col" key={e.id}>
                <span className="parity__env" style={{ background: `var(--color-env-${e.type})` }} />
                {ENV_LABEL[e.type]}
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
                        <Icon name={bad ? 'x' : 'check'} size={14} label={bad ? '다름' : '같음'} />
                        <span className="t-mono-sm">{value}</span>
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
