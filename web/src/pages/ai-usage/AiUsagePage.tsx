import { useState } from 'react'
import { useParams } from 'react-router'
import { api, isMocked } from '../../api/endpoints.ts'
import type { AiUsageItem, AiUsageSummary, Deployment } from '../../api/types.ts'
import { useResource } from '../../api/useResource.ts'
import Alert from '../../components/Alert.tsx'
import DataTable from '../../components/DataTable.tsx'
import EmptyState from '../../components/EmptyState.tsx'
import EnvTag from '../../components/EnvTag.tsx'
import Icon from '../../components/Icon.tsx'
import PageHeader from '../../components/PageHeader.tsx'
import Panel from '../../components/Panel.tsx'
import Select from '../../components/Select.tsx'
import StatTile from '../../components/StatTile.tsx'
import StatusBadge from '../../components/StatusBadge.tsx'
import { t } from '../../i18n/index.ts'
import { clockTime, count, shortCommit, won } from '../../utils/format.ts'
import { names } from '../flow.ts'
import { ErrorBlock, LoadingBlock } from '../Loading.tsx'
import '../page.css'

// W-12 AI 사용량 — 배포를 골라서 그 배포의 AI 호출 · 토큰 · 비용(추정)을 봐요. 차트는 쓰지 않아요
// 합계는 A-05 plan 응답의 ai_usage, 호출별 기록은 GET /projects/{id}/ai-usage?deployment_id= (#13, 10/1 서버 결정)
// plan 전에 멈춘 배포는 plan이 없어서 호출 기록으로 합계를 계산해요. 여러 배포 합계는 예선 범위에서 안 해요
type Row = { key: string; item: AiUsageItem | null; type: Deployment['targets'][number]['type'] }

function AiUsagePage() {
  const { projectId = '' } = useParams()
  const runs = useResource(() => api.listDeployments(projectId), [projectId])
  const [picked, setPicked] = useState<string | null>(null)
  const id = picked ?? runs.data?.items[0]?.id ?? ''
  const deployment = useResource(() => (id ? api.getDeployment(id) : Promise.resolve(null)), [id])
  const calls = useResource(() => (id ? api.listAiUsage(projectId, id) : Promise.resolve(null)), [projectId, id])
  // plan이 없으면(404 등) null로 두고 호출 기록에서 합계를 계산해요
  const plan = useResource(() => (id ? api.getPlan(id).catch(() => null) : Promise.resolve(null)), [id])

  if (runs.error) return <ErrorBlock error={runs.error} />
  if (!runs.data) return <LoadingBlock />
  if (runs.data.items.length === 0) {
    return (
      <div className="page">
        <PageHeader mock={isMocked('listDeployments', 'getDeployment', 'listAiUsage', 'getPlan')} overline="AI usage" title={t('AI 사용량')} />
        <EmptyState icon="signal" title={t('아직 배포가 없어요')} description={t('배포하면 AI를 몇 번, 얼마나 썼는지 여기서 봐요')} />
      </div>
    )
  }

  const d = deployment.data
  const items = calls.data?.items
  const summary = plan.data?.ai_usage ?? (items ? summarize(items) : null)
  const reused = d?.targets.filter((tg) => tg.reused_script) ?? []
  const typeOf = (targetId: string) => d?.targets.find((t) => t.target_id === targetId)?.type ?? 'onprem'
  // Jenkins가 아직 호출별 기록을 안 보내서 빈 목록일 수 있어요 — "AI를 안 썼다"로 보이지 않게 "기록 없음"으로 (#60)
  const noRecord = (items?.length ?? 0) === 0 && (summary?.calls ?? 0) === 0
  // 모든 환경이 검증된 스크립트를 재사용했으면 기록이 없는 게 아니라 AI를 정말 0회 부른 거예요 → 0 · ₩0
  const allReused = noRecord && !!d && d.targets.length > 0 && reused.length === d.targets.length
  const rows: Row[] = [
    ...(items ?? []).map((item, i) => ({ key: `${i}`, item, type: typeOf(item.target_id) })),
    ...reused.map((tg) => ({ key: `reuse-${tg.target_id}`, item: null, type: tg.type })),
  ]

  return (
    <div className="page">
      <PageHeader mock={isMocked('listDeployments', 'getDeployment', 'listAiUsage', 'getPlan')}
        overline="AI usage"
        title={t('AI 사용량')}
        description={t('배포마다 AI를 몇 번, 얼마나 썼는지 봐요. 판단이 필요한 생성 · 수정에만 AI를 쓰고, 검증된 스크립트는 재사용해요.')}
      />

      <div style={{ width: 340 }}>
        <Select
          label={t('배포 고르기')}
          value={id}
          onChange={setPicked}
          leading={<Icon name="git-branch" size={16} />}
          options={runs.data.items.map((r) => ({ value: r.id, label: t('{ver}{commit} · {time} 배포', { ver: r.version ? `${r.version} · ` : '', commit: shortCommit(r.commit), time: clockTime(r.created_at) }) }))}
        />
      </div>

      {deployment.error || calls.error ? (
        <ErrorBlock error={(deployment.error ?? calls.error) as Error} />
      ) : !d || !items || !summary || plan.loading ? (
        <LoadingBlock />
      ) : (
        <>
          <div className="page__row page__row--stats">
            <StatTile
              label={t('AI 호출')}
              value={noRecord && !allReused ? '—' : t('{n}회', { n: summary.calls })}
              hint={allReused ? t('검증된 스크립트를 재사용했어요') : noRecord ? t('기록 없음') : t('이번 배포')}
            />
            <StatTile label={t('토큰')} value={allReused ? count(0) : count(summary.tokens)} hint={t('입력 + 출력')} />
            <StatTile label={t('비용')} value={allReused ? won(0) : won(summary.cost_krw)} hint={summary.exchange_rate ? t('추정 · 환율 {rate}원 · Claude', { rate: count(summary.exchange_rate) }) : t('추정 · Claude')} />
            <StatTile label={t('재사용한 환경')} value={t('{n}곳', { n: reused.length })} hint={reused.length ? t('{names} · AI 호출 0회', { names: names(reused) }) : t('없음')} />
          </div>

          {allReused && (
            <Alert type="success" title={t('검증된 스크립트를 재사용해서 AI를 부르지 않았어요')}>
              {t('모든 환경이 이미지 태그만 바꿔서 배포했어요. 이번 배포의 AI 비용은 ₩0이에요.')}
            </Alert>
          )}
          {noRecord && !allReused && (
            <Alert type="info" title={t('호출 기록을 아직 받지 않았어요')}>
              {t('AI를 안 썼다는 뜻이 아니에요. 생성 · 수정 호출 기록은 Jenkins 연동 뒤에 들어와요.')}
            </Alert>
          )}

          <Panel title={t('이 배포의 호출 기록')}>
            <DataTable
              label={t('이 배포의 호출 기록')}
              rows={rows}
              rowKey={(r) => r.key}
              columns={[
                { key: 'at', label: t('시각'), width: 100, render: (r) => <span className="t-mono-sm">{r.item ? clockTime(r.item.at) : clockTime(d.created_at)}</span> },
                { key: 'env', label: t('환경'), width: 120, render: (r) => <EnvTag env={r.type} /> },
                { key: 'job', label: t('작업'), render: (r) => (r.item ? (r.item.title ?? r.item.note ?? t(STEP_LABEL[r.item.step])) : t('검증된 스크립트 재사용')) },
                { key: 'att', label: t('시도'), width: 80, render: (r) => <span className="t-mono-sm">{r.item?.attempt != null ? `${r.item.attempt}/3` : '—'}</span> },
                { key: 'tok', label: t('토큰'), width: 90, render: (r) => <span className="t-mono-sm">{r.item ? count(r.item.tokens) : '0'}</span> },
                { key: 'cost', label: t('비용'), width: 80, render: (r) => <span className="t-mono-sm">{r.item ? won(r.item.cost_krw) : '₩0'}</span> },
                {
                  key: 'res',
                  label: t('결과'),
                  width: 120,
                  render: (r) =>
                    !r.item ? (
                      <StatusBadge tone="queued">{t('AI 호출 없음')}</StatusBadge>
                    ) : r.item.status === 'succeeded' ? (
                      <StatusBadge tone="success">{t('호출 성공')}</StatusBadge>
                    ) : (
                      <StatusBadge tone="failed">{t('호출 실패')}</StatusBadge>
                    ),
                },
              ]}
            />
          </Panel>

          <p className="t-body-sm t-muted">{t('비용은 토큰 수로 계산한 추정값이에요. 서버가 확인하지 못한 값은 "—"로 보여줘요.')}</p>
        </>
      )}
    </div>
  )
}

const STEP_LABEL: Record<AiUsageItem['step'], string> = { generate: 'Terraform 생성', fix: 'Terraform 수정' }

// 확인 못 한 값(null)이 하나라도 있으면 합계도 null → "—"
function summarize(items: AiUsageItem[]): AiUsageSummary {
  const sum = (pick: (i: AiUsageItem) => number | null) =>
    items.some((i) => pick(i) == null) ? null : items.reduce((acc, i) => acc + (pick(i) ?? 0), 0)
  return { calls: items.length, tokens: sum((i) => i.tokens), cost_krw: sum((i) => i.cost_krw), exchange_rate: 0, estimated: true }
}

export default AiUsagePage
