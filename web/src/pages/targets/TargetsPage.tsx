import { useState } from 'react'
import { useNavigate, useParams, useSearchParams } from 'react-router'
import { ApiError } from '../../api/client.ts'
import { api } from '../../api/endpoints.ts'
import { useResource } from '../../api/useResource.ts'
import Alert from '../../components/Alert.tsx'
import Button from '../../components/Button.tsx'
import { ENV_LABEL } from '../../components/env.ts'
import EnvSelectCard from '../../components/EnvSelectCard.tsx'
import InfoRow from '../../components/InfoRow.tsx'
import PageHeader from '../../components/PageHeader.tsx'
import Panel from '../../components/Panel.tsx'
import Stepper from '../../components/Stepper.tsx'
import { paths } from '../../paths.ts'
import { shortCommit } from '../../utils/format.ts'
import { ErrorBlock, LoadingBlock } from '../Loading.tsx'
import '../page.css'

// W-04 배포할 환경 선택 (STEP 3) — 여러 환경을 동시에, 카드에 재사용 / 새로 생성 판단을 미리 보여줘요 (WR-04)
function TargetsPage() {
  const { projectId = '' } = useParams()
  const [params] = useSearchParams()
  const navigate = useNavigate()
  const targets = useResource(() => api.listTargets(projectId), [projectId])
  const builds = useResource(() => api.listBuilds(projectId), [projectId])
  const [unselected, setUnselected] = useState<Set<string>>(new Set())
  const [error, setError] = useState<string | null>(null)
  const [pending, setPending] = useState(false)

  if (targets.error) return <ErrorBlock error={targets.error} />
  if (!targets.data || !builds.data) return <LoadingBlock />

  const build = builds.data.items.find((b) => b.commit === params.get('commit')) ?? builds.data.items[0]
  const commit = build?.commit ?? ''
  const selected = targets.data.filter((t) => !unselected.has(t.target_id) && t.connection.state !== 'failed')
  const reuse = selected.filter((t) => t.reuse.available)
  const generate = selected.filter((t) => !t.reuse.available)
  const names = (list: typeof selected) => list.map((t) => ENV_LABEL[t.type]).join(', ')

  const toggle = (id: string, on: boolean) =>
    setUnselected((prev) => {
      const next = new Set(prev)
      if (on) next.delete(id)
      else next.add(id)
      return next
    })

  const start = async () => {
    setPending(true)
    setError(null)
    try {
      const d = await api.createDeployment(projectId, commit, selected.map((t) => t.target_id))
      navigate(paths.generate(projectId, d.id), { state: { transition: 'l02' } })
    } catch (e) {
      setError(e instanceof ApiError ? e.message : '배포를 시작하지 못했어요')
      setPending(false)
    }
  }

  return (
    <div className="page">
      <Stepper current={3} />
      <PageHeader
        overline="Step 3"
        title="배포할 환경 선택"
        description={`여러 환경을 동시에 고를 수 있어요. 같은 이미지(${shortCommit(commit)})가 모든 환경에 배포돼요.`}
      />

      <div className="page__row page__row--3">
        {targets.data.map((t) => (
          <EnvSelectCard
            key={t.target_id}
            env={t.type}
            title={t.title ?? t.name}
            description={t.connection.state === 'failed' ? '연결할 수 없어요 · 환경 화면에서 확인해 주세요' : t.reuse.reason}
            selected={!unselected.has(t.target_id) && t.connection.state !== 'failed'}
            disabled={t.connection.state === 'failed'}
            onChange={(on) => toggle(t.target_id, on)}
          />
        ))}
      </div>

      <Panel title="선택 요약">
        <div>
          <InfoRow label="선택한 환경">{`${selected.length}개`}</InfoRow>
          <InfoRow label="스크립트 재사용">{reuse.length ? `${reuse.length}개 · ${names(reuse)}` : '없음'}</InfoRow>
          <InfoRow label="AI가 새로 생성">{generate.length ? `${generate.length}개 · ${names(generate)}` : '없음'}</InfoRow>
          <InfoRow label="배포할 이미지">{build?.image ?? '—'}</InfoRow>
        </div>
      </Panel>

      {error && (
        <Alert type="danger" title="배포를 시작하지 못했어요">
          {error}
        </Alert>
      )}

      <div className="page__actions">
        <Button variant="ghost" onClick={() => navigate(paths.build(projectId))}>
          이전
        </Button>
        <Button variant="secondary" disabled={selected.length === 0 || pending} onClick={() => void start()}>
          {pending ? '시작하는 중…' : '인프라 코드 생성 · 검증 시작'}
        </Button>
      </div>
    </div>
  )
}

export default TargetsPage
