import { useState } from 'react'
import { useParams } from 'react-router'
import { attemptLabel } from '../../api/status.ts'
import { api } from '../../api/endpoints.ts'
import type { Script } from '../../api/types.ts'
import { useResource } from '../../api/useResource.ts'
import Alert from '../../components/Alert.tsx'
import CodeBlock from '../../components/CodeBlock.tsx'
import DataTable from '../../components/DataTable.tsx'
import EmptyState from '../../components/EmptyState.tsx'
import { ENV_LABEL } from '../../components/env.ts'
import EnvTag from '../../components/EnvTag.tsx'
import InfoRow from '../../components/InfoRow.tsx'
import PageHeader from '../../components/PageHeader.tsx'
import Panel from '../../components/Panel.tsx'
import Tabs from '../../components/Tabs.tsx'
import { clockTime, count, relativeTime, shortCommit } from '../../utils/format.ts'
import { ErrorBlock, LoadingBlock } from '../Loading.tsx'
import '../page.css'
import './ScriptsPage.css'

// W-11 스크립트 — AI가 만들고 검증을 통과한 Terraform (WR-10). 폐기된 것도 남겨서 "몇 번 만에 통과했는지" 보여줘요
// 저장 위치는 [미정]
function ScriptsPage() {
  const { projectId = '' } = useParams()
  const scripts = useResource(() => api.listScripts(projectId), [projectId])
  if (scripts.error) return <ErrorBlock error={scripts.error} />
  if (!scripts.data) return <LoadingBlock />
  return <ScriptsView scripts={scripts.data} />
}

function howMade(s: Script) {
  if (s.status === 'discarded') return `AI 생성 · ${s.attempt}회 실패 → 폐기`
  return `${s.origin === 'reused' ? '재사용' : 'AI 생성'} · ${attemptLabel(s.attempt)} 통과${s.note ? ` (${s.note})` : ''}`
}

function ScriptsView({ scripts }: { scripts: Script[] }) {
  const verified = scripts.filter((s) => s.status === 'verified')
  const [selected, setSelected] = useState(verified.find((s) => s.type === 'aws')?.script_id ?? scripts[0]?.script_id)
  const current = scripts.find((s) => s.script_id === selected) ?? scripts[0]

  if (!current) {
    return (
      <div className="page">
        <PageHeader overline="Scripts" title="스크립트" />
        <EmptyState icon="terminal" title="아직 검증된 스크립트가 없어요" description="첫 배포에서 AI가 만든 Terraform이 검증을 통과하면 여기에 쌓여요" />
      </div>
    )
  }

  const file = current.files?.[0]

  return (
    <div className="page">
      <PageHeader
        overline="Scripts"
        title="스크립트"
        description="AI가 만들고 검증을 통과한 Terraform이에요. 같은 환경에 다시 배포할 땐 이미지 태그만 바꿔 재사용해서 AI를 부르지 않아요."
      />

      <Panel title="검증된 스크립트">
        <DataTable
          label="검증된 스크립트"
          rows={scripts}
          rowKey={(s) => s.script_id}
          selected={current.script_id}
          onSelect={(s) => setSelected(s.script_id)}
          columns={[
            { key: 'env', label: '환경', width: 120, render: (s) => <EnvTag env={s.type} /> },
            { key: 'v', label: '버전', width: 90, render: (s) => <span className="t-mono-sm">{s.version}</span> },
            { key: 'how', label: '만든 방식', render: howMade },
            { key: 'check', label: '검증', width: 180, render: (s) => (s.validation.plan ? `validate · plan · 위험 ${s.validation.risks}` : 'plan 실패') },
            { key: 'reuse', label: '재사용', width: 90, render: (s) => (s.status === 'verified' ? `${s.reuse_count}회` : '—') },
            { key: 'last', label: '마지막 사용', width: 110, render: (s) => relativeTime(s.last_used_at) },
          ]}
        />
      </Panel>

      <div className="scripts__bottom">
        <Panel title={`${file?.path ?? `${current.type}/main.tf`} · ${current.version}`}>
          <Tabs
            label="환경별 스크립트"
            value={current.type}
            onChange={(type) => setSelected(verified.find((s) => s.type === type)?.script_id ?? current.script_id)}
            items={(['onprem', 'aws', 'gcp'] as const).map((t) => ({ id: t, label: ENV_LABEL[t], env: t }))}
          />
          {file ? (
            <CodeBlock
              ai={current.origin !== 'reused'}
              file={`${file.path} · ${current.origin === 'reused' ? '재사용' : 'AI 생성'} · ${attemptLabel(current.attempt)}`}
              code={file.content}
            />
          ) : (
            <p className="t-body-sm t-muted">폐기된 스크립트는 내용을 보관하지 않아요.</p>
          )}
        </Panel>

        <Panel title="정보">
          <div>
            <InfoRow label="기준 이미지">{current.base_commit ? shortCommit(current.base_commit) : '—'}</InfoRow>
            <InfoRow label="입력">{current.input ?? '—'}</InfoRow>
            <InfoRow label="AI 토큰">{current.ai_tokens === undefined ? '—' : count(current.ai_tokens)}</InfoRow>
            <InfoRow label="저장 위치">{current.storage ?? '[미정]'}</InfoRow>
            <InfoRow label="만든 시각">
              {current.created_at ? `${new Date(current.created_at).getMonth() + 1}/${new Date(current.created_at).getDate()} ${clockTime(current.created_at)}` : '—'}
            </InfoRow>
          </div>
          {current.status === 'verified' && (
            <Alert type="info" title="다음 배포는 재사용">
              이미지 태그만 바꿔서 AI 호출 0회로 배포해요.
            </Alert>
          )}
        </Panel>
      </div>
    </div>
  )
}

export default ScriptsPage
