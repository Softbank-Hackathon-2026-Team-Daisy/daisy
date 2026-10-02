import { useState } from 'react'
import { useParams } from 'react-router'
import { ApiError, USE_MOCK } from '../../api/client.ts'
import { api, isMocked } from '../../api/endpoints.ts'
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
import { t } from '../../i18n/index.ts'
import { shortCommit } from '../../utils/format.ts'
import { ErrorBlock, LoadingBlock } from '../Loading.tsx'
import '../page.css'

// W-10 환경 — 대상 환경의 연결 상태와 인프라 구성. 환경을 고르는 건 배포할 때(W-04)
// 연결 테스트(A-10) · 리소스 보기(A-11)는 #13 가칭. "환경 추가"는 예선 범위 결정 전이라 비활성
function EnvironmentsPage() {
  const { projectId = '' } = useParams()
  const targets = useResource(() => api.listTargets(projectId), [projectId])
  // WR-04 current_commit이 비어 있을 때가 있어서 A-02 현재 버전으로 채워요. 실패해도 화면은 그대로 보여줘요
  const status = useResource(() => api.getTargetsStatus(projectId).catch(() => null), [projectId])
  const [toast, setToast] = useState<{ ok: boolean; text: string } | null>(null)
  const [resourcesOf, setResourcesOf] = useState<Target | null>(null)

  const probeReady = USE_MOCK || !isMocked('testTarget', 'listTargetResources')

  if (targets.error) return <ErrorBlock error={targets.error} />
  if (!targets.data) return <LoadingBlock />

  const test = async (tg: Target) => {
    try {
      const r = await api.testTarget(tg.target_id)
      setToast({ ok: r.connected, text: r.message })
    } catch (e) {
      setToast({ ok: false, text: e instanceof ApiError ? e.message : t('연결 테스트를 하지 못했어요') })
    }
  }

  return (
    <div className="page">
      <PageHeader mock={isMocked('listTargets')} overline="Environments" title={t('환경')} description={t('배포 대상 환경의 연결 상태와 인프라 구성을 봐요. 환경을 고르는 건 배포할 때 해요.')} />

      <div className="page__row page__row--envs">
        {targets.data.items.map((tg) => {
          const st = status.data?.items.find((x) => x.target_id === tg.target_id)
          const commit = tg.current_commit ?? st?.current?.commit ?? null
          const exposure = tg.exposure ?? st?.url ?? null
          return (
          <Panel key={tg.target_id} title={<EnvTag env={tg.type} />} aside={<ConnectionBadge state={tg.connection.state} />}>
            <div>
              <InfoRow label={t('유형')}>{tg.runtime ?? tg.title ?? '—'}</InfoRow>
              <InfoRow label={t(tg.location_label ?? '위치')}>{tg.location ? (isInternal(tg.location) ? t('내부망') : tg.location) : '—'}</InfoRow>
              <InfoRow label={t('연결')}>{tg.access_method ?? '—'}</InfoRow>
              <InfoRow label={t('공개')}>{exposure ? <Exposure value={exposure} /> : '—'}</InfoRow>
              <InfoRow label="state">{tg.state_backend ?? t('[미정]')}</InfoRow>
              <InfoRow label={t('현재 버전')}>{commit ? shortCommit(commit) : '—'}</InfoRow>
            </div>
            <div className="page__actions">
              {/* 실서버 모드에서 A-10 · A-11이 아직 없으면 목업 결과를 실제 환경처럼 보이지 않게 꺼요 (#13 후순위) */}
              <Button variant="outline" disabled={!probeReady} onClick={() => void test(tg)}>
                {t('연결 테스트')}
              </Button>
              <Button variant="ghost" disabled={!probeReady} onClick={() => setResourcesOf(tg)}>
                {t('리소스 보기')}
              </Button>
            </div>
          </Panel>
          )
        })}
      </div>

      <Panel title={t('환경 추가')}>
        <p className="t-body-sm t-muted">
          {t('퍼블릭 클라우드(소규모 사업자 포함)나 다른 온프레미스 서버를 대상 환경으로 추가해요. 준비된 기준 모듈이 없어도 AI가 deploy.yaml로 Terraform을 처음부터 만들어요.')}
        </p>
        <div className="page__actions" style={{ alignItems: 'center' }}>
          <Button variant="outline" disabled title={t('예선 범위 결정 전이에요')}>
            {t('+ 환경 추가')}
          </Button>
          <span className="t-body-sm t-muted">{t('예선에서는 온프레미스 · AWS · GCP · Azure 4개 환경을 써요')}</span>
        </div>
      </Panel>

      {toast && (
        <Toast type={toast.ok ? 'success' : 'error'} title={toast.text} onClose={() => setToast(null)} />
      )}
      {resourcesOf && <ResourcesDialog target={resourcesOf} onClose={() => setResourcesOf(null)} />}
    </div>
  )
}

// 사설 · 내부 주소(10.x · 172.16~31.x · 192.168.x · 127.x · *.local · *.internal)가 들어 있으면 화면에 그대로 보이지 않게 가려요
function isInternalHost(token: string) {
  const host = token.replace(/^[a-z]+:\/\//i, '').split(/[/:]/)[0].toLowerCase()
  const m = host.match(/^(\d{1,3})\.(\d{1,3})\.\d{1,3}\.\d{1,3}$/)
  if (m) {
    const [a, b] = [Number(m[1]), Number(m[2])]
    return a === 10 || a === 127 || (a === 172 && b >= 16 && b <= 31) || (a === 192 && b === 168)
  }
  return /\.(local|internal|lan)$/.test(host) || host === 'localhost'
}

const isInternal = (value: string) => value.split(/[\s,()·]+/).some((token) => token && isInternalHost(token))

// 공개 주소가 URL로 시작하면 그 부분을 새 탭 링크로 (예: "gcp.unibloom.cloud (도메인 매핑)")
// 줄바꿈은 단어 중간이 아니라 '.' · '/' 뒤에서만 해요
const URL_HEAD = /^((?:https?:\/\/)?[a-z0-9-]+(?:\.[a-z0-9-]+)+(?::\d+)?(?:\/\S*)?)(.*)$/i

function Exposure({ value }: { value: string }) {
  if (isInternal(value)) return <>{t('내부망')}</>
  const m = value.match(URL_HEAD)
  if (!m) return <>{value}</>
  const [, url, rest] = m
  const href = /^https?:\/\//i.test(url) ? url : `https://${url}`
  const parts = url.split(/(?<=[./])/)
  return (
    <>
      <a href={href} target="_blank" rel="noreferrer" style={{ overflowWrap: 'normal', wordBreak: 'normal' }}>
        {parts.map((part, i) => (
          <span key={i}>
            {part}
            {i < parts.length - 1 && <wbr />}
          </span>
        ))}
      </a>
      {rest}
    </>
  )
}

function ConnectionBadge({ state }: { state: Target['connection']['state'] }) {
  if (state === 'ok') return <StatusBadge tone="success">{t('연결됨')}</StatusBadge>
  if (state === 'failed') return <StatusBadge tone="failed">{t('연결 안 됨')}</StatusBadge>
  return <StatusBadge tone="queued">{t('확인 전')}</StatusBadge>
}

function ResourcesDialog({ target, onClose }: { target: Target; onClose: () => void }) {
  const list = useResource(() => api.listTargetResources(target.target_id), [target.target_id])
  return (
    <Dialog
      open
      onClose={onClose}
      icon="database"
      title={t('{name} 리소스', { name: target.title ?? target.name })}
      description={t('Terraform state에 기록된 리소스예요.')}
      actions={
        <Button variant="outline" onClick={onClose}>
          {t('닫기')}
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
