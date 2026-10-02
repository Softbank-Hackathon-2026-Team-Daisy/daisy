import { useState } from 'react'
import { useNavigate, useParams } from 'react-router'
import { useAuth } from '../../api/auth.ts'
import { api, isMocked } from '../../api/endpoints.ts'
import { deploymentStatus } from '../../api/status.ts'
import type { Deployment } from '../../api/types.ts'
import { useAction } from '../../api/useAction.ts'
import { pollFor, useProjectLive } from '../../api/projectLive.ts'
import { useResource } from '../../api/useResource.ts'
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
import { t } from '../../i18n/index.ts'
import { clockTime, relativeTime, shortCommit } from '../../utils/format.ts'
import { envName, names, versionLabel } from '../flow.ts'
import { ErrorBlock, LoadingBlock } from '../Loading.tsx'
import '../page.css'

// W-09 배포 이력 · 롤백 — 롤백은 이전 성공 배포의 커밋 + 검증된 스크립트로 만드는 새 배포예요 (WR-14, plan · 승인을 거쳐요)

function HistoryPage() {
  const { projectId = '' } = useParams()
  const { state: live, tick } = useProjectLive()
  const runs = useResource(() => api.listDeployments(projectId), [projectId, tick], pollFor(live))
  // 롤백 확인 단어도 프로젝트 이름(A-12)
  const project = useResource(() => api.getProject(projectId), [projectId])
  const name = project.data?.name ?? ''
  const [target, setTarget] = useState<Deployment | null>(null)

  if (runs.error) return <ErrorBlock error={runs.error} />
  if (!runs.data) return <LoadingBlock />

  return (
    <div className="page">
      <PageHeader mock={isMocked('listDeployments', 'rollback')} overline="History" title={t('배포 이력')} description={t('버전마다 어떤 이미지와 스크립트로 어느 환경에 배포했는지 남겨요.')} />
      <Panel title={name || t('배포 이력')}>
        {runs.data.items.length === 0 ? (
          <EmptyState icon="clock" title={t('아직 배포 이력이 없어요')} description={t('첫 배포를 하면 여기에 쌓여요')} />
        ) : (
          <HistoryTable projectId={projectId} rows={runs.data.items} onRollback={setTarget} />
        )}
      </Panel>
      {target && <RollbackDialog projectId={projectId} projectName={name} from={target} onClose={() => setTarget(null)} />}
    </div>
  )
}

function HistoryTable({ projectId, rows, onRollback }: { projectId: string; rows: Deployment[]; onRollback: (d: Deployment) => void }) {
  const navigate = useNavigate()
  const { role } = useAuth()
  const latestOk = rows.find((d) => d.state === 'succeeded')
  return (
    <DataTable
      label={t('배포 이력')}
      rows={rows}
      rowKey={(d) => d.id}
      columns={[
        { key: 'v', label: t('버전'), width: 80, render: (d) => <span className="t-mono">{versionLabel(d)}</span> },
        { key: 'c', label: t('커밋'), width: 110, render: (d) => <span className="t-mono">{shortCommit(d.commit)}</span> },
        {
          key: 's',
          label: t('상태'),
          width: 110,
          render: (d) => {
            const s = deploymentStatus(d.state, d.kind)
            return <StatusBadge tone={s.tone}>{d.kind === 'rollback' ? t('롤백 · {status}', { status: s.label }) : s.label}</StatusBadge>
          },
        },
        {
          key: 'e',
          label: t('환경'),
          render: (d) => (
            <span style={{ display: 'inline-flex', gap: 'var(--space-1)' }}>
              {d.targets.map((tg) => (
                <EnvTag key={tg.target_id} env={tg.type} />
              ))}
            </span>
          ),
        },
        {
          key: 'by',
          label: t('배포자'),
          width: 120,
          render: (d) => (
            <span style={{ display: 'inline-flex', alignItems: 'center', gap: 'var(--space-2)' }}>
              <Avatar type="human" name={d.created_by} />
              {d.created_by}
            </span>
          ),
        },
        { key: 't', label: t('시간'), width: 150, render: (d) => `${clockTime(d.created_at)} · ${relativeTime(d.created_at)}` },
        {
          key: 'a',
          label: '',
          width: 90,
          render: (d) =>
            d.state === 'awaiting_approval' ? (
              <Button variant="ghost" onClick={() => navigate(paths.approve(projectId, d.id))}>
                {t('승인하기')}
              </Button>
            ) : d.state === 'succeeded' && d.id !== latestOk?.id ? (
              <Button variant="ghost" disabled={role === 'viewer'} onClick={() => onRollback(d)}>
                {t('롤백')}
              </Button>
            ) : (
              <Button variant="ghost" onClick={() => navigate(paths.result(projectId, d.id))}>
                {t('결과')}
              </Button>
            ),
        },
      ]}
    />
  )
}

function RollbackDialog({ projectId, projectName, from, onClose }: { projectId: string; projectName: string; from: Deployment; onClose: () => void }) {
  const navigate = useNavigate()
  const [picked, setPicked] = useState(() => new Set(from.targets.map((tg) => tg.target_id)))
  const [confirm, setConfirm] = useState('')
  const { run, pending, error } = useAction()
  const chosen = from.targets.filter((tg) => picked.has(tg.target_id))

  const toggle = (id: string, on: boolean) =>
    setPicked((prev) => {
      const next = new Set(prev)
      if (on) next.add(id)
      else next.delete(id)
      return next
    })

  const start = async () => {
    // 롤백 사유는 서버에 남는 값이라 화면 언어와 상관없이 한국어로 보내요 (#74 안 A)
    const d = await run((key) => api.rollback(from.id, chosen.map((tg) => tg.target_id), `${versionLabel(from)}로 롤백`, key), t('롤백을 시작하지 못했어요'))
    if (d) navigate(paths.generate(projectId, d.id), { state: { transition: 'l02' } })
  }

  return (
    <Dialog
      open
      onClose={onClose}
      icon="rotate-ccw"
      title={t('{version}로 롤백 배포를 시작할까요?', { version: versionLabel(from) })}
      description={t('{version}({commit}) 이미지로 새 배포를 만들어서 {names}에 다시 올려요. 검증된 스크립트를 재사용해서 AI는 부르지 않아요. plan을 확인하고 승인해야 적용돼요.', {
        version: versionLabel(from),
        commit: shortCommit(from.commit),
        names: names(chosen) || t('고른 환경'),
      })}
      actions={
        <>
          <Button variant="outline" onClick={onClose}>
            {t('취소')}
          </Button>
          <Button variant="destructive" disabled={pending || chosen.length === 0 || !projectName || confirm !== projectName} onClick={() => void start()}>
            {pending ? t('시작하는 중…') : t('롤백 배포 시작')}
          </Button>
        </>
      }
    >
      <div style={{ display: 'flex', gap: 'var(--space-3)', flexWrap: 'wrap' }}>
        {from.targets.map((tg) => (
          <Checkbox key={tg.target_id} checked={picked.has(tg.target_id)} onChange={(e) => toggle(tg.target_id, e.target.checked)}>
            {envName(tg)}
          </Checkbox>
        ))}
      </div>
      <label style={{ display: 'flex', flexDirection: 'column', gap: 6 }}>
        <span className="t-body-sm t-muted">{t('확인을 위해 프로젝트 이름({name})을 입력해 주세요.', { name: projectName })}</span>
        <Input value={confirm} onChange={(e) => setConfirm(e.target.value)} placeholder={projectName} />
      </label>
      {error && <Alert type="danger" title={t('롤백을 시작하지 못했어요')}>{error}</Alert>}
    </Dialog>
  )
}

export default HistoryPage
