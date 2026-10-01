import { useState } from 'react'
import { useNavigate, useParams } from 'react-router'
import { useAuth } from '../../api/auth.ts'
import { api } from '../../api/endpoints.ts'
import { deploymentStatus } from '../../api/status.ts'
import type { Deployment } from '../../api/types.ts'
import { useAction } from '../../api/useAction.ts'
import { POLL_MS, useResource } from '../../api/useResource.ts'
import Alert from '../../components/Alert.tsx'
import Avatar from '../../components/Avatar.tsx'
import Button from '../../components/Button.tsx'
import Checkbox from '../../components/Checkbox.tsx'
import DataTable from '../../components/DataTable.tsx'
import Dialog from '../../components/Dialog.tsx'
import EmptyState from '../../components/EmptyState.tsx'
import EnvTag from '../../components/EnvTag.tsx'
import Input from '../../components/Input.tsx'
import PageHeader from '../../components/PageHeader.tsx'
import Panel from '../../components/Panel.tsx'
import StatusBadge from '../../components/StatusBadge.tsx'
import { paths } from '../../paths.ts'
import { clockTime, relativeTime, shortCommit } from '../../utils/format.ts'
import { envName, names } from '../flow.ts'
import { ErrorBlock, LoadingBlock } from '../Loading.tsx'
import '../page.css'

// W-09 배포 이력 · 롤백 — 롤백은 이전 성공 배포의 커밋 + 검증된 스크립트로 만드는 새 배포예요 (WR-14, plan · 승인을 거쳐요)
// MOCK: 프로젝트 이름은 A-01이 열리면 서버 값으로
const PROJECT_NAME = 'sample-monolith'

function HistoryPage() {
  const { projectId = '' } = useParams()
  const runs = useResource(() => api.listDeployments(projectId), [projectId], POLL_MS)
  const [target, setTarget] = useState<Deployment | null>(null)

  if (runs.error) return <ErrorBlock error={runs.error} />
  if (!runs.data) return <LoadingBlock />

  return (
    <div className="page">
      <PageHeader overline="History" title="배포 이력" description="버전마다 어떤 이미지와 스크립트로 어느 환경에 배포했는지 남겨요." />
      <Panel title={PROJECT_NAME}>
        {runs.data.items.length === 0 ? (
          <EmptyState icon="clock" title="아직 배포 이력이 없어요" description="첫 배포를 하면 여기에 쌓여요" />
        ) : (
          <HistoryTable projectId={projectId} rows={runs.data.items} onRollback={setTarget} />
        )}
      </Panel>
      {target && <RollbackDialog projectId={projectId} from={target} onClose={() => setTarget(null)} />}
    </div>
  )
}

function HistoryTable({ projectId, rows, onRollback }: { projectId: string; rows: Deployment[]; onRollback: (d: Deployment) => void }) {
  const navigate = useNavigate()
  const { role } = useAuth()
  const latestOk = rows.find((d) => d.state === 'succeeded')
  return (
    <DataTable
      label="배포 이력"
      rows={rows}
      rowKey={(d) => d.id}
      columns={[
        { key: 'v', label: '버전', width: 80, render: (d) => <span className="t-mono">{d.version}</span> },
        { key: 'c', label: '커밋', width: 110, render: (d) => <span className="t-mono">{shortCommit(d.commit)}</span> },
        {
          key: 's',
          label: '상태',
          width: 110,
          render: (d) => {
            const s = deploymentStatus(d.state, d.kind)
            return <StatusBadge tone={s.tone}>{d.kind === 'rollback' ? `롤백 · ${s.label}` : s.label}</StatusBadge>
          },
        },
        {
          key: 'e',
          label: '환경',
          render: (d) => (
            <span style={{ display: 'inline-flex', gap: 'var(--space-1)' }}>
              {d.targets.map((t) => (
                <EnvTag key={t.target_id} env={t.type} />
              ))}
            </span>
          ),
        },
        {
          key: 'by',
          label: '배포자',
          width: 120,
          render: (d) => (
            <span style={{ display: 'inline-flex', alignItems: 'center', gap: 'var(--space-2)' }}>
              <Avatar type="human" name={d.created_by} />
              {d.created_by}
            </span>
          ),
        },
        { key: 't', label: '시간', width: 150, render: (d) => `${clockTime(d.created_at)} · ${relativeTime(d.created_at)}` },
        {
          key: 'a',
          label: '',
          width: 90,
          render: (d) =>
            d.state === 'awaiting_approval' ? (
              <Button variant="ghost" onClick={() => navigate(paths.approve(projectId, d.id))}>
                승인하기
              </Button>
            ) : d.state === 'succeeded' && d.id !== latestOk?.id ? (
              <Button variant="ghost" disabled={role === 'viewer'} onClick={() => onRollback(d)}>
                롤백
              </Button>
            ) : (
              <Button variant="ghost" onClick={() => navigate(paths.result(projectId, d.id))}>
                결과
              </Button>
            ),
        },
      ]}
    />
  )
}

function RollbackDialog({ projectId, from, onClose }: { projectId: string; from: Deployment; onClose: () => void }) {
  const navigate = useNavigate()
  const [picked, setPicked] = useState(() => new Set(from.targets.map((t) => t.target_id)))
  const [confirm, setConfirm] = useState('')
  const { run, pending, error } = useAction()
  const chosen = from.targets.filter((t) => picked.has(t.target_id))

  const toggle = (id: string, on: boolean) =>
    setPicked((prev) => {
      const next = new Set(prev)
      if (on) next.add(id)
      else next.delete(id)
      return next
    })

  const start = async () => {
    const d = await run((key) => api.rollback(from.id, chosen.map((t) => t.target_id), `${from.version}로 롤백`, key), '롤백을 시작하지 못했어요')
    if (d) navigate(paths.generate(projectId, d.id), { state: { transition: 'l02' } })
  }

  return (
    <Dialog
      open
      onClose={onClose}
      icon="rotate-ccw"
      title={`${from.version}로 롤백 배포를 시작할까요?`}
      description={`${from.version}(${shortCommit(from.commit)}) 이미지로 새 배포를 만들어서 ${names(chosen) || '고른 환경'}에 다시 올려요. 검증된 스크립트를 재사용해서 AI는 부르지 않아요. plan을 확인하고 승인해야 적용돼요.`}
      actions={
        <>
          <Button variant="outline" onClick={onClose}>
            취소
          </Button>
          <Button variant="destructive" disabled={pending || chosen.length === 0 || confirm !== PROJECT_NAME} onClick={() => void start()}>
            {pending ? '시작하는 중…' : '롤백 배포 시작'}
          </Button>
        </>
      }
    >
      <div style={{ display: 'flex', gap: 'var(--space-3)', flexWrap: 'wrap' }}>
        {from.targets.map((t) => (
          <Checkbox key={t.target_id} checked={picked.has(t.target_id)} onChange={(e) => toggle(t.target_id, e.target.checked)}>
            {envName(t)}
          </Checkbox>
        ))}
      </div>
      <label style={{ display: 'flex', flexDirection: 'column', gap: 6 }}>
        <span className="t-body-sm t-muted">확인을 위해 프로젝트 이름({PROJECT_NAME})을 입력해 주세요.</span>
        <Input value={confirm} onChange={(e) => setConfirm(e.target.value)} placeholder={PROJECT_NAME} />
      </label>
      {error && <Alert type="danger" title="롤백을 시작하지 못했어요">{error}</Alert>}
    </Dialog>
  )
}

export default HistoryPage
