import { useNavigate, useParams } from 'react-router'
import { api, isMocked } from '../../api/endpoints.ts'
import type { Build } from '../../api/types.ts'
import { POLL_MS, useResource } from '../../api/useResource.ts'
import Button from '../../components/Button.tsx'
import ConnectionIndicator from '../../components/ConnectionIndicator.tsx'
import EmptyState from '../../components/EmptyState.tsx'
import InfoRow from '../../components/InfoRow.tsx'
import PageHeader from '../../components/PageHeader.tsx'
import Panel from '../../components/Panel.tsx'
import RunListItem from '../../components/RunListItem.tsx'
import StepItem, { type StepItemState } from '../../components/StepItem.tsx'
import Stepper from '../../components/Stepper.tsx'
import { paths } from '../../paths.ts'
import { duration, shortCommit } from '../../utils/format.ts'
import TransitionGate from '../loading/TransitionGate.tsx'
import { ErrorBlock, LoadingBlock } from '../Loading.tsx'
import '../page.css'

// W-03 이미지 빌드 (STEP 2) — main merge를 감지하면 Jenkins 빌드 진행을 보여줘요 (9/30 회의). 서버 SSE 전까지 5초 폴링, 끝나면 멈춰요
const STEP_STATE: Record<string, StepItemState> = { waiting: 'pending', running: 'running', done: 'done', failed: 'failed', skipped: 'skipped' }

function BuildPage() {
  const { projectId = '' } = useParams()
  const builds = useResource(() => api.listBuilds(projectId), [projectId], POLL_MS, (b) => b.items[0]?.pipeline.status === 'success' || b.items[0]?.pipeline.status === 'failed')
  // L-01: 저장소를 연결하고 넘어왔으면 첫 빌드가 나타날 때까지 전환 로딩
  const ready = !!builds.data && builds.data.items.length > 0

  return (
    <TransitionGate kind="l01" ready={ready} meta="Step 1 · Repo">
      {builds.error ? (
        <ErrorBlock error={builds.error} />
      ) : !builds.data ? (
        <LoadingBlock />
      ) : (
        <BuildView projectId={projectId} build={builds.data.items[0]} />
      )}
    </TransitionGate>
  )
}

function BuildView({ projectId, build }: { projectId: string; build: Build | undefined }) {
  const navigate = useNavigate()
  const status = build?.pipeline.status

  return (
    <div className="page">
      <Stepper current={2} />
      <PageHeader
        overline="Step 2"
        mock={isMocked('listBuilds')}
        title="이미지 빌드"
        description={
          !build
            ? 'main에 merge하면 Jenkins가 이미지를 빌드해요.'
            : status === 'success'
            ? '이미지가 준비됐어요. 배포할 환경을 골라 주세요.'
            : status === 'failed'
              ? '빌드 · 테스트가 실패해서 멈췄어요. 실패한 단계를 확인해 주세요.'
              : status === 'queued'
                ? 'main merge를 감지했어요. Jenkins가 빌드를 시작하기를 기다리고 있어요.'
                : 'main merge를 감지했어요. Jenkins가 이미지를 만들고 있어요.'
        }
      />

      {!build ? (
        <EmptyState icon="git-merge" title="아직 빌드가 없어요" description="main에 merge하면 여기에 나타나요" />
      ) : (
        <>
          <div className="page__list">
            <RunListItem
              tone={status === 'success' ? 'success' : status === 'failed' ? 'failed' : status === 'queued' ? 'queued' : 'running'}
              label={status === 'success' ? '빌드 완료' : status === 'failed' ? '빌드 실패' : status === 'queued' ? '대기 중' : '빌드 중'}
              commit={build.commit}
              message={build.message}
              author={build.author}
              at={build.committed_at ?? build.received_at}
            />
          </div>

          <div className="page__row page__row--2">
            <Panel title="Jenkins">
              <div>
                {/* 단계는 Jenkins 이벤트 연동 뒤에 와요 (#13 답: 인프라 확인 대기) */}
                {!build.pipeline.steps?.length && <p className="t-body-sm t-muted">단계 정보는 Jenkins 연동 뒤에 보여요</p>}
                {(build.pipeline.steps ?? []).map((s) => (
                  <StepItem
                    key={s.name}
                    state={STEP_STATE[s.state] ?? 'pending'}
                    label={s.name}
                    duration={duration(s.duration_ms, s.state === 'running')}
                  />
                ))}
              </div>
              {/* Jenkins 화면은 배포 키가 있어 외부 비공개 — 로그 열기 버튼 없이 서버가 넘겨준 단계만 보여줘요 (#17 인프라 답) */}
            </Panel>

            <Panel title="이미지">
              <div>
                <InfoRow label="커밋">{shortCommit(build.commit)}</InfoRow>
                <InfoRow label="브랜치">{build.branch ?? '—'}</InfoRow>
                <InfoRow label="이미지">{build.image ?? '—'}</InfoRow>
                <InfoRow label="digest">{build.image_digest ?? '—'}</InfoRow>
                {/* 서비스가 여럿이면 image · image_digest 대신 서비스별로 와요 (#38) */}
                {build.images?.map((im) => (
                  <InfoRow key={im.service} label={im.service}>{`${im.image_ref ?? '—'} · ${im.image_digest ?? '—'}`}</InfoRow>
                ))}
              </div>
              <div>
                {/* 서버 SSE(D3) 전까지는 폴링 */}
                <ConnectionIndicator state="polling" />
              </div>
            </Panel>
          </div>

          <div className="page__actions">
            <Button
              variant="secondary"
              disabled={status !== 'success'}
              onClick={() => navigate(`${paths.targets(projectId)}?${build.source_version_id ? `build=${build.source_version_id}` : `commit=${build.commit}`}`)}
            >
              배포할 환경 고르기
            </Button>
          </div>
        </>
      )}
    </div>
  )
}

export default BuildPage
