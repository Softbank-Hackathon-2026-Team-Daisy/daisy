import { useState } from 'react'
import { useNavigate, useParams } from 'react-router'
import { useAuth } from '../../api/auth.ts'
import { ApiError } from '../../api/client.ts'
import { api } from '../../api/endpoints.ts'
import { useResource } from '../../api/useResource.ts'
import Alert from '../../components/Alert.tsx'
import Button from '../../components/Button.tsx'
import CodeBlock from '../../components/CodeBlock.tsx'
import Dialog from '../../components/Dialog.tsx'
import EmptyState from '../../components/EmptyState.tsx'
import InfoRow from '../../components/InfoRow.tsx'
import LanguageSelect from '../../components/LanguageSelect.tsx'
import Input from '../../components/Input.tsx'
import PageHeader from '../../components/PageHeader.tsx'
import Panel from '../../components/Panel.tsx'
import Toggle from '../../components/Toggle.tsx'
import { t } from '../../i18n/index.ts'
import { paths } from '../../paths.ts'
import { clockTime } from '../../utils/format.ts'
import { ErrorBlock, LoadingBlock } from '../Loading.tsx'
import '../page.css'

// W-13 설정 — 저장소(A-12) · 배포 명세(WR-03, 읽기 전용) · 비밀값(WR-12, 전달 방식 [미정]) · 알림 · 연결 해제(WR-13)
// 알림 설정은 저장 API가 없어서 이 브라우저에서만 기억해요 (가칭)
const NOTIFY = [
  { key: 'approval', label: '승인이 필요할 때 · Swift 앱 푸시', on: true },
  { key: 'done', label: '배포가 끝났을 때', on: true },
  { key: 'failed', label: '배포가 실패했을 때', on: true },
  { key: 'browser', label: '브라우저 알림', on: false },
]

function SettingsPage() {
  const { projectId = '' } = useParams()
  const project = useResource(() => api.getProject(projectId), [projectId])
  const manifest = useResource(() => api.getManifest(projectId), [projectId])
  const error = project.error ?? manifest.error
  if (error) return <ErrorBlock error={error} />
  if (!project.data || !manifest.data) return <LoadingBlock />
  const p = project.data
  const m = manifest.data
  return (
    <div className="page">
      <PageHeader overline="Settings" title={t('설정')} description={t('이 프로젝트의 저장소 연결, 배포 명세, 비밀값, 알림을 관리해요.')} />

      <div className="page__row page__row--2" style={{ alignItems: 'start' }}>
        <Panel title={t('저장소')}>
          <div>
            <InfoRow label="GitHub">
              {p.repository_url ? (
                <a href={p.repository_url} target="_blank" rel="noopener noreferrer">
                  {p.repository}
                </a>
              ) : (
                p.repository
              )}
            </InfoRow>
            <InfoRow label={t('기준 브랜치')}>{p.default_branch ?? '—'}</InfoRow>
            <InfoRow label={t('배포 명세')}>{p.manifest_path ?? '—'}</InfoRow>
            {/* 빌드 · 레지스트리 · 웹훅은 서버 미제공 (#13 10/1 답) — 오면 보여줘요 */}
            <InfoRow label={t('빌드')}>{p.build ?? 'Jenkins daisy-ci'}</InfoRow>
            <InfoRow label={t('레지스트리')}>{t('{registry} [미정]', { registry: p.registry ?? '—' })}</InfoRow>
            <InfoRow label={t('웹훅')}>{p.webhook_last_at ? t('수신 중 · 마지막 {time}', { time: clockTime(p.webhook_last_at) }) : '—'}</InfoRow>
          </div>
          <ReconnectButton />
        </Panel>

        <Panel title={t('배포 명세 (deploy.yaml)')}>
          <p className="t-body-sm t-muted">{t('저장소의 deploy.yaml이 기준이에요. 여기서는 읽기만 해요.')}</p>
          <CodeBlock file={m.ref} code={m.raw ?? `port: ${m.port}\nhealthcheck: ${m.healthcheck}`} />
        </Panel>
      </div>

      <div className="page__row page__row--2" style={{ alignItems: 'start' }}>
        <Panel title={t('비밀값')}>
          <p className="t-body-sm t-muted">{t('deploy.yaml의 secrets에 적힌 이름만 값을 넣어요. 값은 다시 볼 수 없어요.')}</p>
          {m.secrets.length === 0 ? (
            <EmptyState
              icon="lock"
              title={t('이 앱은 비밀값이 없어요')}
              description={t('secrets: [] · 전달 방식(GitHub Secrets / 시크릿 매니저 / 서버 암호화 저장)은 [미정]')}
              action={
                <Button variant="outline" disabled>
                  {t('비밀값 추가')}
                </Button>
              }
            />
          ) : (
            <div>
              {m.secrets.map((name) => (
                <InfoRow key={name} label={name}>
                  {t('●●●● (전달 방식 [미정])')}
                </InfoRow>
              ))}
            </div>
          )}
        </Panel>

        <div style={{ display: 'grid', gap: 'var(--space-6)' }}>
          <Panel title={t('알림')}>
            <Notifications />
          </Panel>

          {/* 화면 언어는 프로젝트가 아니라 이 브라우저 설정이에요 (#75) */}
          <Panel title={t('화면 언어')}>
            <p className="t-body-sm t-muted">{t('이 브라우저에만 적용돼요. 서버가 보내는 메시지는 받은 그대로 보여줘요.')}</p>
            <LanguageSelect />
          </Panel>
        </div>
      </div>

      <Disconnect projectId={projectId} name={p.name} />
    </div>
  )
}

function ReconnectButton() {
  const navigate = useNavigate()
  return (
    <div>
      <Button variant="outline" onClick={() => navigate(paths.connect())}>
        {t('저장소 다시 연결')}
      </Button>
    </div>
  )
}

function Notifications() {
  const [state, setState] = useState<Record<string, boolean>>(() => {
    try {
      const saved = localStorage.getItem('unibloom.notify')
      if (saved) return JSON.parse(saved) as Record<string, boolean>
    } catch {
      // 저장소를 못 쓰면 기본값으로
    }
    return Object.fromEntries(NOTIFY.map((n) => [n.key, n.on]))
  })
  const set = (key: string, on: boolean) => {
    const next = { ...state, [key]: on }
    setState(next)
    try {
      localStorage.setItem('unibloom.notify', JSON.stringify(next))
    } catch {
      // 무시해요
    }
  }
  return (
    <div>
      {NOTIFY.map((n) => (
        <div key={n.key} style={{ display: 'flex', alignItems: 'center', gap: 'var(--space-3)', padding: '10px 0', borderBottom: 'var(--border)' }}>
          <span className="t-body-sm" style={{ flex: 1 }}>
            {t(n.label)}
          </span>
          <Toggle label={t(n.label)} checked={!!state[n.key]} onChange={(on) => set(n.key, on)} />
        </div>
      ))}
    </div>
  )
}

function Disconnect({ projectId, name }: { projectId: string; name: string }) {
  const navigate = useNavigate()
  const { role } = useAuth()
  const [open, setOpen] = useState(false)
  const [confirm, setConfirm] = useState('')
  const [error, setError] = useState<string | null>(null)
  const run = async () => {
    try {
      await api.deleteProject(projectId)
      navigate(paths.connect())
    } catch (e) {
      setError(e instanceof ApiError ? e.message : t('연결을 해제하지 못했어요'))
    }
  }
  return (
    <Panel title={t('프로젝트 연결 해제')}>
      <p className="t-body-sm t-muted">{t('배포 서비스에서 이 프로젝트를 지워요. 이미 떠 있는 인프라는 지워지지 않아요 (terraform destroy는 따로 해요).')}</p>
      <div>
        <Button variant="destructive" disabled={role === 'viewer'} onClick={() => setOpen(true)}>
          {t('연결 해제')}
        </Button>
      </div>
      {open && (
        <Dialog
          open
          onClose={() => setOpen(false)}
          icon="alert-triangle"
          title={t('{name} 연결을 해제할까요?', { name })}
          description={t('되돌릴 수 없어요. 떠 있는 인프라는 그대로 남아요. 확인을 위해 프로젝트 이름을 입력해 주세요.')}
          actions={
            <>
              <Button variant="outline" onClick={() => setOpen(false)}>
                {t('취소')}
              </Button>
              <Button variant="destructive" disabled={confirm !== name} onClick={() => void run()}>
                {t('연결 해제')}
              </Button>
            </>
          }
        >
          <Input value={confirm} onChange={(e) => setConfirm(e.target.value)} placeholder={name} />
          {error && <Alert type="danger" title={t('연결을 해제하지 못했어요')}>{error}</Alert>}
        </Dialog>
      )}
    </Panel>
  )
}

export default SettingsPage
