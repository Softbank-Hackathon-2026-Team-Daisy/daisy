import { useState } from 'react'
import { useParams } from 'react-router'
import { attemptLabel } from '../../api/status.ts'
import { api, isMocked } from '../../api/endpoints.ts'
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
import { t } from '../../i18n/index.ts'
import { clockTime, count, relativeTime, shortCommit } from '../../utils/format.ts'
import { ErrorBlock, LoadingBlock } from '../Loading.tsx'
import '../page.css'
import './ScriptsPage.css'

// W-11 스크립트 — AI가 만들고 검증을 통과한 Terraform (WR-10, #68). 원본을 더 쓸 수 없는 것(폐기)도 남겨서 보여줘요
// 파일 내용은 WR-07이라 실서버에서는 아직 없어요. 저장 위치 · 입력 · 토큰은 서버에 원천이 없어 "—"예요
function ScriptsPage() {
  const { projectId = '' } = useParams()
  const scripts = useResource(() => api.listScripts(projectId), [projectId])
  if (scripts.error) return <ErrorBlock error={scripts.error} />
  if (!scripts.data) return <LoadingBlock />
  return <ScriptsView scripts={scripts.data} />
}

// 만든 방식 — origin이 null이면 AI 없이 기준 모듈을 썼거나 출처를 몰라요 (#68). AI 생성이라고 하지 않아요
const originLabel = (s: Script) => (s.origin === 'reused' ? t('재사용') : s.origin === 'ai_generated' ? t('AI 생성') : t('출처 미확인'))

function howMade(s: Script) {
  if (s.status === 'discarded') return t('{origin} · 원본을 더 쓸 수 없어 폐기', { origin: originLabel(s) })
  const how = s.attempt == null ? originLabel(s) : t('{origin} · {attempt} 통과', { origin: originLabel(s), attempt: attemptLabel(s.attempt) })
  return s.note ? `${how} (${s.note})` : how
}

// 재사용할 때마다 새 버전이 생겨서(s1…s11) 환경마다 최신 하나만 보여주고, 이전 버전은 펼쳐서 봐요
const ENV_ORDER = ['onprem', 'aws', 'gcp', 'azure']
const versionNo = (s: Script) => Number(s.version.match(/\d+/)?.[0] ?? 0)
const newerFirst = (a: Script, b: Script) =>
  a.created_at && b.created_at && a.created_at !== b.created_at ? b.created_at.localeCompare(a.created_at) : versionNo(b) - versionNo(a)

function groupByEnv(scripts: Script[]) {
  const groups = new Map<string, Script[]>()
  for (const s of scripts) groups.set(s.target_id, [...(groups.get(s.target_id) ?? []), s])
  return [...groups.values()]
    .map((list) => list.sort(newerFirst))
    .sort((a, b) => ENV_ORDER.indexOf(a[0].type) - ENV_ORDER.indexOf(b[0].type))
}

type Row = { script: Script; latest: boolean; older: number; groupId: string }

function ScriptsView({ scripts }: { scripts: Script[] }) {
  const groups = groupByEnv(scripts)
  const ordered = groups.flat()
  const verified = ordered.filter((s) => s.status === 'verified')
  const [selected, setSelected] = useState(verified.find((s) => s.type === 'aws')?.script_id ?? ordered[0]?.script_id)
  const [expanded, setExpanded] = useState<Set<string>>(() => new Set())
  const current = scripts.find((s) => s.script_id === selected) ?? ordered[0]
  const toggle = (groupId: string) =>
    setExpanded((prev) => {
      const next = new Set(prev)
      if (next.has(groupId)) next.delete(groupId)
      else next.add(groupId)
      return next
    })
  const rows: Row[] = groups.flatMap((list) => {
    const groupId = list[0].target_id
    const head: Row = { script: list[0], latest: true, older: list.length - 1, groupId }
    return expanded.has(groupId) ? [head, ...list.slice(1).map((script) => ({ script, latest: false, older: 0, groupId }))] : [head]
  })

  if (!current) {
    return (
      <div className="page">
        <PageHeader mock={isMocked('listScripts')} overline="Scripts" title={t('스크립트')} />
        <EmptyState icon="terminal" title={t('아직 검증된 스크립트가 없어요')} description={t('첫 배포에서 AI가 만든 Terraform이 검증을 통과하면 여기에 쌓여요')} />
      </div>
    )
  }

  const file = current.files?.[0]

  return (
    <div className="page">
      <PageHeader
        mock={isMocked('listScripts')}
        overline="Scripts"
        title={t('스크립트')}
        description={t('AI가 만들고 검증을 통과한 Terraform이에요. 같은 환경에 다시 배포할 땐 이미지 태그만 바꿔 재사용해서 AI를 부르지 않아요.')}
      />

      <Panel title={t('검증된 스크립트')}>
        <DataTable
          label={t('검증된 스크립트')}
          rows={rows}
          rowKey={(r) => r.script.script_id}
          selected={current.script_id}
          onSelect={(r) => setSelected(r.script.script_id)}
          columns={[
            { key: 'env', label: t('환경'), width: 120, render: (r) => (r.latest ? <EnvTag env={r.script.type} /> : <span className="t-muted scripts__older">{t('이전 버전')}</span>) },
            { key: 'v', label: t('버전'), width: 90, render: (r) => <span className="t-mono-sm">{r.script.version}</span> },
            {
              key: 'how',
              label: t('만든 방식'),
              render: (r) => (
                <div className="scripts__how">
                  <span>{howMade(r.script)}</span>
                  {r.latest && r.older > 0 && (
                    <button
                      type="button"
                      className="scripts__toggle t-body-sm"
                      aria-expanded={expanded.has(r.groupId)}
                      onClick={(e) => {
                        e.stopPropagation()
                        toggle(r.groupId)
                      }}
                    >
                      {expanded.has(r.groupId) ? t('이전 버전 접기') : t('이전 버전 {n}개 보기', { n: r.older })}
                    </button>
                  )}
                </div>
              ),
            },
            { key: 'check', label: t('검증'), width: 180, render: ({ script: s }) => (s.validation.plan ? t('validate · plan · 위험 {n}', { n: s.validation.risks ?? '—' }) : t('validate 통과 · plan 없음')) },
            { key: 'reuse', label: t('재사용'), width: 90, render: ({ script: s }) => (s.status === 'verified' ? t('{n}회', { n: s.reuse_count }) : '—') },
            { key: 'last', label: t('마지막 사용'), width: 110, render: ({ script: s }) => (s.last_used_at ? relativeTime(s.last_used_at) : '—') },
          ]}
        />
      </Panel>

      <div className="scripts__bottom">
        <Panel title={`${file?.path ?? `${current.type}/main.tf`} · ${current.version}`}>
          <Tabs
            label={t('환경별 스크립트')}
            value={current.type}
            onChange={(type) => setSelected(verified.find((s) => s.type === type)?.script_id ?? current.script_id)}
            items={(['onprem', 'aws', 'gcp', 'azure'] as const).map((env) => ({ id: env, label: t(ENV_LABEL[env]), env }))}
          />
          {file ? (
            <CodeBlock
              ai={current.origin === 'ai_generated'}
              file={`${file.path} · ${originLabel(current)} · ${attemptLabel(current.attempt)}`}
              code={file.content}
            />
          ) : (
            <p className="t-body-sm t-muted">
              {current.status === 'discarded' ? t('폐기된 스크립트는 내용을 보관하지 않아요.') : t('생성된 스크립트는 서버 연결(WR-07) 뒤에 보여요')}
            </p>
          )}
        </Panel>

        <Panel title={t('정보')}>
          <div>
            <InfoRow label={t('기준 이미지')}>{current.base_commit ? shortCommit(current.base_commit) : '—'}</InfoRow>
            <InfoRow label={t('입력')}>{current.input ?? '—'}</InfoRow>
            <InfoRow label={t('AI 토큰')}>{current.ai_tokens === undefined ? '—' : count(current.ai_tokens)}</InfoRow>
            <InfoRow label={t('저장 위치')}>{current.storage ?? t('[미정]')}</InfoRow>
            <InfoRow label={t('만든 시각')}>
              {current.created_at ? `${new Date(current.created_at).getMonth() + 1}/${new Date(current.created_at).getDate()} ${clockTime(current.created_at)}` : '—'}
            </InfoRow>
          </div>
          {current.status === 'verified' && (
            <Alert type="info" title={t('다음 배포는 재사용')}>
              {t('이미지 태그만 바꿔서 AI 호출 0회로 배포해요.')}
            </Alert>
          )}
        </Panel>
      </div>
    </div>
  )
}

export default ScriptsPage
