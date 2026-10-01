import { useState } from 'react'
import { useParams } from 'react-router'
import { ApiError } from '../../api/client.ts'
import { api } from '../../api/endpoints.ts'
import type { Target } from '../../api/types.ts'
import { useResource } from '../../api/useResource.ts'
import Button from '../../components/Button.tsx'
import Dialog from '../../components/Dialog.tsx'
import EnvTag from '../../components/EnvTag.tsx'
import InfoRow from '../../components/InfoRow.tsx'
import PageHeader from '../../components/PageHeader.tsx'
import Panel from '../../components/Panel.tsx'
import StatusBadge from '../../components/StatusBadge.tsx'
import Toast from '../../components/Toast.tsx'
import { shortCommit } from '../../utils/format.ts'
import { ErrorBlock, LoadingBlock } from '../Loading.tsx'
import '../page.css'

// W-10 환경 — 대상 환경의 연결 상태와 인프라 구성. 환경을 고르는 건 배포할 때(W-04)
// 연결 테스트(A-10) · 리소스 보기(A-11)는 #13 가칭. "환경 추가"는 예선 범위 결정 전이라 비활성
function EnvironmentsPage() {
  const { projectId = '' } = useParams()
  const targets = useResource(() => api.listTargets(projectId), [projectId])
  const [toast, setToast] = useState<{ ok: boolean; text: string } | null>(null)
  const [resourcesOf, setResourcesOf] = useState<Target | null>(null)

  if (targets.error) return <ErrorBlock error={targets.error} />
  if (!targets.data) return <LoadingBlock />

  const test = async (t: Target) => {
    try {
      const r = await api.testTarget(t.target_id)
      setToast({ ok: r.connected, text: r.message })
    } catch (e) {
      setToast({ ok: false, text: e instanceof ApiError ? e.message : '연결 테스트를 하지 못했어요' })
    }
  }

  return (
    <div className="page">
      <PageHeader overline="Environments" title="환경" description="배포 대상 환경의 연결 상태와 인프라 구성을 봐요. 환경을 고르는 건 배포할 때 해요." />

      <div className="page__row page__row--3">
        {targets.data.map((t) => (
          <Panel key={t.target_id} title={<EnvTag env={t.type} />} aside={<ConnectionBadge state={t.connection.state} />}>
            <div>
              <InfoRow label="유형">{t.runtime ?? t.title ?? '—'}</InfoRow>
              <InfoRow label={t.location_label ?? '위치'}>{t.location ?? '—'}</InfoRow>
              <InfoRow label="연결">{t.access_method ?? '—'}</InfoRow>
              <InfoRow label="공개">{t.exposure ?? '—'}</InfoRow>
              <InfoRow label="state">{t.state_backend ?? '[미정]'}</InfoRow>
              <InfoRow label="현재 버전">{t.current_commit ? shortCommit(t.current_commit) : '—'}</InfoRow>
            </div>
            <div className="page__actions">
              <Button variant="outline" onClick={() => void test(t)}>
                연결 테스트
              </Button>
              <Button variant="ghost" onClick={() => setResourcesOf(t)}>
                리소스 보기
              </Button>
            </div>
          </Panel>
        ))}
      </div>

      <Panel title="환경 추가">
        <p className="t-body-sm t-muted">
          퍼블릭 클라우드(소규모 사업자 포함)나 다른 온프레미스 서버를 대상 환경으로 추가해요. 준비된 기준 모듈이 없어도 AI가 deploy.yaml로 Terraform을 처음부터 만들어요.
        </p>
        <div className="page__actions" style={{ alignItems: 'center' }}>
          <Button variant="outline" disabled title="예선 범위 결정 전이에요">
            + 환경 추가
          </Button>
          <EnvTag env="azure" />
          <span className="t-body-sm t-muted">예선 범위 결정 전이에요</span>
        </div>
      </Panel>

      {toast && (
        <Toast type={toast.ok ? 'success' : 'error'} title={toast.text} onClose={() => setToast(null)} />
      )}
      {resourcesOf && <ResourcesDialog target={resourcesOf} onClose={() => setResourcesOf(null)} />}
    </div>
  )
}

function ConnectionBadge({ state }: { state: Target['connection']['state'] }) {
  if (state === 'ok') return <StatusBadge tone="success">연결됨</StatusBadge>
  if (state === 'failed') return <StatusBadge tone="failed">연결 안 됨</StatusBadge>
  return <StatusBadge tone="queued">확인 전</StatusBadge>
}

function ResourcesDialog({ target, onClose }: { target: Target; onClose: () => void }) {
  const list = useResource(() => api.listTargetResources(target.target_id), [target.target_id])
  return (
    <Dialog
      open
      onClose={onClose}
      icon="database"
      title={`${target.title ?? target.name} 리소스`}
      description="Terraform state에 기록된 리소스예요."
      actions={
        <Button variant="outline" onClick={onClose}>
          닫기
        </Button>
      }
    >
      {list.data ? (
        <div>
          {list.data.items.map((r) => (
            <InfoRow key={r.address} label={r.type.split('_')[0]}>
              {r.address}
            </InfoRow>
          ))}
        </div>
      ) : (
        <LoadingBlock />
      )}
    </Dialog>
  )
}

export default EnvironmentsPage
