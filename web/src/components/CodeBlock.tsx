import { useState } from 'react'
import { t } from '../i18n/index.ts'
import Icon from './Icon.tsx'
import './CodeBlock.css'

// Figma 「05 · Code Block」. 생성된 Terraform · plan 출력. +/- 로 시작하는 줄은 diff 색으로 보여줘요
type CodeBlockProps = {
  file: string
  code: string
  ai?: boolean
}

function CodeBlock({ file, code, ai = false }: CodeBlockProps) {
  const [copied, setCopied] = useState(false)
  const copy = async () => {
    await navigator.clipboard?.writeText(code)
    setCopied(true)
    window.setTimeout(() => setCopied(false), 1500)
  }
  return (
    <figure className="code-block">
      <figcaption className="code-block__header">
        {ai && <span className="code-block__ai">AI</span>}
        <span className="t-label">{file}</span>
        <button type="button" className="code-block__copy" aria-label={copied ? t('복사했어요') : t('코드 복사')} onClick={() => void copy()}>
          <Icon name={copied ? 'check' : 'copy'} size={16} />
        </button>
      </figcaption>
      <pre className="code-block__body">
        {code.split('\n').map((line, i) => (
          <span key={i} className={line.startsWith('+') ? 'code-block__add' : line.startsWith('-') ? 'code-block__del' : undefined}>
            {line}
            {'\n'}
          </span>
        ))}
      </pre>
    </figure>
  )
}

export default CodeBlock
