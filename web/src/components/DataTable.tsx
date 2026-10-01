import type { ReactNode } from 'react'
import './DataTable.css'

// Figma 「06 · History Table Row」와 W-11 · W-12 표. 머리줄은 surface, 줄마다 아래 1px line
export type Column<T> = { key: string; label: string; width?: number | string; render: (row: T) => ReactNode }

type DataTableProps<T> = {
  columns: Column<T>[]
  rows: T[]
  rowKey: (row: T) => string
  selected?: string
  onSelect?: (row: T) => void
  label: string
}

function DataTable<T>({ columns, rows, rowKey, selected, onSelect, label }: DataTableProps<T>) {
  return (
    <div className="data-table__wrap">
      <table className="data-table" aria-label={label}>
        <thead>
          <tr>
            {columns.map((c) => (
              <th key={c.key} scope="col" style={{ width: c.width }}>
                {c.label}
              </th>
            ))}
          </tr>
        </thead>
        <tbody>
          {rows.map((row) => {
            const key = rowKey(row)
            return (
              <tr
                key={key}
                className={[onSelect && 'data-table__row--clickable', selected === key && 'data-table__row--selected'].filter(Boolean).join(' ') || undefined}
                onClick={onSelect ? () => onSelect(row) : undefined}
              >
                {columns.map((c) => (
                  <td key={c.key}>{c.render(row)}</td>
                ))}
              </tr>
            )
          })}
        </tbody>
      </table>
    </div>
  )
}

export default DataTable
