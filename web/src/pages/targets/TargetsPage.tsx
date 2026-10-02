import { useState } from 'react'
import { useNavigate, useParams, useSearchParams } from 'react-router'
import { useAuth } from '../../api/auth.ts'
import { api, isMocked } from '../../api/endpoints.ts'
import { useAction } from '../../api/useAction.ts'
import { useResource } from '../../api/useResource.ts'
import Alert from '../../components/Alert.tsx'
import Button from '../../components/Button.tsx'
import { ENV_LABEL } from '../../components/env.ts'
import EnvSelectCard from '../../components/EnvSelectCard.tsx'
import InfoRow from '../../components/InfoRow.tsx'
import PageHeader from '../../components/PageHeader.tsx'
import Panel from '../../components/Panel.tsx'
import Stepper from '../../components/Stepper.tsx'
import { t } from '../../i18n/index.ts'
import { paths } from '../../paths.ts'
import { shortCommit } from '../../utils/format.ts'
import { ErrorBlock, LoadingBlock } from '../Loading.tsx'
import ReadOnlyNote from '../ReadOnlyNote.tsx'
import '../page.css'

// W-04 배포할 환경 선택 (STEP 3) — 여러 환경을 동시에, 카드에 재사용 / 새로 생성 판단을 미리 보여줘요 (WR-04)
function TargetsPage() {
  const { projectId = '' } = useParams()
  const [params] = useSearchParams()
  const navigate = useNavigate()
  const targets = useResource(() => api.listTargets(projectId), [projectId])
  const builds = useResource(() => api.listBuilds(projectId), [projectId])
  const [unselected, setUnselected] = useState<Set<string>>(new Set())
  const { run, pending, error } = useAction()
  const viewer = useAuth().role === 'viewer'

  if (targets.error) return <ErrorBlock error={targets.error} />
  if (!targets.data || !builds.data) return <LoadingBlock />

  // 빌드는 source_version_id(?build=)로 골라요. 같은 커밋이 여러 번 빌드될 수 있어서예요 (#19 · #36)
  const build =
    builds.data.items.find((b) => (params.get('build') ? b.source_version_id === params.get('build') : b.commit === params.get('commit'))) ??
    builds.data.items.find((b) => b.pipeline.status === 'success') ??
    builds.data.items[0]
  const commit = build?.commit ?? ''
  const list = targets.data.items
  const selected = list.filter((tg) => !unselected.has(tg.target_id) && tg.connection.state !== 'failed')
  // reuse가 null이면 인프라가 아직 판단을 안 준 거라 "확인 전"으로 따로 세요 (#42)
  const reuse = selected.filter((tg) => tg.reuse?.available === true)
  const generate = selected.filter((tg) => tg.reuse?.available === false)
  const unknown = selected.filter((tg) => !tg.reuse)
  const names = (list: typeof selected) => list.map((tg) => t(ENV_LABEL[tg.type])).join(', ')

  const toggle = (id: string, on: boolean) =>
    setUnselected((prev) => {
      const next = new Set(prev)
      if (on) next.delete(id)
      else next.add(id)
      return next
    })

  const start = async () => {
    const d = await run((key) => api.createDeployment(projectId, { source_version_id: build?.source_version_id, commit }, selected.map((tg) => tg.target_id), key), t('배포를 시작하지 못했어요'))
    if (d) navigate(paths.generate(projectId, d.id), { state: { transition: 'l02' } })
  }

  return (
    <div className="page">
      <Stepper current={3} />
      <PageHeader mock={isMocked('listTargets', 'listBuilds', 'createDeployment')}
        overline="Step 3"
        title={t('배포할 환경 선택')}
        description={t('여러 환경을 동시에 고를 수 있어요. 같은 이미지({commit})가 모든 환경에 배포돼요.', { commit: shortCommit(commit) })}
      />

      <div className="page__row page__row--envs">
        {list.map((tg) => (
          <EnvSelectCard
            key={tg.target_id}
            env={tg.type}
            title={tg.title ?? tg.name}
            description={
              tg.connection.state === 'failed'
                ? t('연결할 수 없어요 · 환경 화면에서 확인해 주세요')
                : (tg.reuse?.reason ?? (tg.connection.state === 'unknown' ? t('연결 확인 전 · 재사용 여부는 생성할 때 정해져요') : t('재사용 여부는 생성할 때 정해져요')))
            }
            selected={!unselected.has(tg.target_id) && tg.connection.state !== 'failed'}
            disabled={tg.connection.state === 'failed'}
            onChange={(on) => toggle(tg.target_id, on)}
          />
        ))}
      </div>

      <Panel title={t('선택 요약')}>
        <div>
          <InfoRow label={t('선택한 환경')}>{t('{count}개', { count: selected.length })}</InfoRow>
          <InfoRow label={t('스크립트 재사용')}>{reuse.length ? t('{count}개 · {names}', { count: reuse.length, names: names(reuse) }) : t('없음')}</InfoRow>
          <InfoRow label={t('AI가 새로 생성')}>{generate.length ? t('{count}개 · {names}', { count: generate.length, names: names(generate) }) : t('없음')}</InfoRow>
          {unknown.length > 0 && <InfoRow label={t('판단 전')}>{t('{count}개 · {names}', { count: unknown.length, names: names(unknown) })}</InfoRow>}
          <InfoRow label={t('배포할 이미지')}>{build?.image ?? '—'}</InfoRow>
        </div>
      </Panel>

      {error && (
        <Alert type="danger" title={t('배포를 시작하지 못했어요')}>
          {error}
        </Alert>
      )}

      {viewer && <ReadOnlyNote message={t('읽기 전용 계정이라 배포를 시작할 수 없어요.')} />}

      <div className="page__actions">
        <Button variant="ghost" onClick={() => navigate(paths.build(projectId))}>
          {t('이전')}
        </Button>
        <Button variant="secondary" disabled={viewer || selected.length === 0 || pending} onClick={() => void start()}>
          {pending ? t('시작하는 중…') : t('인프라 코드 생성 · 검증 시작')}
        </Button>
      </div>
    </div>
  )
}

export default TargetsPage
