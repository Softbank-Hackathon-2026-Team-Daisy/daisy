import { useState } from 'react'

// 개발용 확인 페이지의 테마 전환 (system · light · dark)
type Theme = 'system' | 'light' | 'dark'

function ThemeToggle() {
  const [theme, setTheme] = useState<Theme>(
    () => (document.documentElement.getAttribute('data-theme') as Theme | null) ?? 'system',
  )

  const applyTheme = (next: Theme) => {
    setTheme(next)
    if (next === 'system') document.documentElement.removeAttribute('data-theme')
    else document.documentElement.setAttribute('data-theme', next)
  }

  return (
    <div className="dev-theme">
      {(['system', 'light', 'dark'] as const).map((t) => (
        <button key={t} type="button" aria-pressed={theme === t} onClick={() => applyTheme(t)}>
          {t}
        </button>
      ))}
    </div>
  )
}

export default ThemeToggle
