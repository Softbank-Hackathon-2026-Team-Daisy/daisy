import { useState } from 'react'
import { useNavigate } from 'react-router'
import { ApiError } from '../../api/client.ts'
import { api } from '../../api/endpoints.ts'
import type { Manifest } from '../../api/types.ts'
import Alert from '../../components/Alert.tsx'
import Button from '../../components/Button.tsx'
import DetectedChip from '../../components/DetectedChip.tsx'
import EmptyState from '../../components/EmptyState.tsx'
import Icon from '../../components/Icon.tsx'
import InfoRow from '../../components/InfoRow.tsx'
import Input from '../../components/Input.tsx'
import PageHeader from '../../components/PageHeader.tsx'
import Panel from '../../components/Panel.tsx'
import Select from '../../components/Select.tsx'
import SourceOptionCard from '../../components/SourceOptionCard.tsx'
import Stepper from '../../components/Stepper.tsx'
import { MOCK_PROJECTS } from '../../mocks/workspace.ts'
import { paths } from '../../paths.ts'
import '../page.css'

// W-02 애플리케이션 연결 (STEP 1) — 입력은 GitHub 저장소 하나 (ADR-004, 업로드 W-02b는 범위 제외)
const GITHUB_URL = /^https:\/\/github\.com\/[\w.-]+\/[\w.-]+\/?$/

// 브랜치 목록 API가 없어서 기준 브랜치는 흔한 이름만 골라요 (가칭)
const BRANCHES = [
  { value: 'main', label: 'main' },
  { value: 'develop', label: 'develop' },
]

function ConnectPage() {
  const navigate = useNavigate()
  const [url, setUrl] = useState('https://github.com/team-daisy/sample-monolith')
  const [branch, setBranch] = useState('main')
  const [manifest, setManifest] = useState<Manifest | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [pending, setPending] = useState(false)
  const valid = GITHUB_URL.test(url.trim())

  const connect = async () => {
    setPending(true)
    setError(null)
    try {
      const res = await api.createProject(url.trim(), branch)
      setManifest(res.manifest)
      if (res.manifest.errors.length === 0) navigate(paths.build(res.project.id), { state: { transition: 'l01' } })
    } catch (e) {
      setError(e instanceof ApiError ? e.message : '연결하지 못했어요')
    } finally {
      setPending(false)
    }
  }

  const preview = manifest

  return (
    <div className="page">
      <Stepper current={1} />
      <PageHeader overline="Step 1" title="애플리케이션 연결" description="배포할 저장소를 연결해요. 처음 한 번만 하면 돼요." />

      <div>
        <SourceOptionCard icon="git-merge" title="GitHub 레포 연결" description="main에 merge하면 Jenkins가 이미지를 빌드해요" selected />
      </div>

      <div className="page__row page__row--2">
        <Panel title="저장소">
          <label style={{ display: 'flex', flexDirection: 'column', gap: 6 }}>
            <span className="t-label">저장소 URL</span>
            <Input value={url} invalid={!!url && !valid} onChange={(e) => setUrl(e.target.value)} placeholder="https://github.com/team/app" />
            {url && !valid && <span className="t-body-sm" style={{ color: 'var(--color-danger)' }}>https://github.com/소유자/저장소 형식으로 적어 주세요</span>}
          </label>
          <div style={{ display: 'flex', flexDirection: 'column', gap: 6 }}>
            <span className="t-label">배포 기준 브랜치</span>
            <Select label="배포 기준 브랜치" value={branch} options={BRANCHES} onChange={setBranch} leading={<Icon name="git-branch" size={16} />} />
          </div>
          <Alert type="info" title="안내">
            {branch}에 merge할 때마다 이미지가 커밋 해시 태그로 만들어져요.
          </Alert>
        </Panel>

        <Panel title="배포 명세 확인">
          {preview ? (
            <>
              <div style={{ display: 'flex', gap: 'var(--space-2)' }}>
                <DetectedChip label="Dockerfile" />
                <DetectedChip label="deploy.yaml" found={preview.errors.length === 0} />
              </div>
              <div>
                <InfoRow label="포트">{preview.port}</InfoRow>
                <InfoRow label="헬스체크 경로">{preview.healthcheck}</InfoRow>
                <InfoRow label="환경변수">{preview.env.length ? `${preview.env[0]}${preview.env.length > 1 ? ` 외 ${preview.env.length - 1}개` : ''}` : '없음'}</InfoRow>
                <InfoRow label="DB 필요">{preview.database ? '예' : '아니요 (상태 없는 앱)'}</InfoRow>
              </div>
              {preview.errors.map((m) => (
                <Alert key={m} type="danger" title="deploy.yaml을 확인해 주세요">
                  {m}
                </Alert>
              ))}
            </>
          ) : (
            <EmptyState icon="search" title="연결하면 배포 명세를 읽어요" description="저장소의 Dockerfile과 deploy.yaml(포트 · 헬스체크 · 환경변수 · DB)을 확인해요" />
          )}
        </Panel>
      </div>

      {error && (
        <Alert type="danger" title="연결하지 못했어요">
          {error}
        </Alert>
      )}

      <div className="page__actions">
        <Button variant="ghost" onClick={() => navigate(paths.overview(MOCK_PROJECTS[0].id))}>
          취소
        </Button>
        {/* 노란색은 배포 버튼 전용이라 여기 CTA는 Secondary */}
        <Button variant="secondary" disabled={!valid || pending} onClick={() => void connect()}>
          {pending ? '연결하는 중…' : '연결하기'}
        </Button>
      </div>
    </div>
  )
}

export default ConnectPage
