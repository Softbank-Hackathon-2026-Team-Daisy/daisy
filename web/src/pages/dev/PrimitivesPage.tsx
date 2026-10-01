import { useState } from 'react'
import Alert from '../../components/Alert.tsx'
import Avatar from '../../components/Avatar.tsx'
import Button from '../../components/Button.tsx'
import Dialog from '../../components/Dialog.tsx'
import EmptyState from '../../components/EmptyState.tsx'
import Icon from '../../components/Icon.tsx'
import { ICON_PATHS, type IconName } from '../../components/icons.ts'
import Input from '../../components/Input.tsx'
import ProgressBar from '../../components/ProgressBar.tsx'
import Select from '../../components/Select.tsx'
import Skeleton from '../../components/Skeleton.tsx'
import Spinner from '../../components/Spinner.tsx'
import Tabs from '../../components/Tabs.tsx'
import Toast from '../../components/Toast.tsx'
import Toggle from '../../components/Toggle.tsx'
import Tooltip from '../../components/Tooltip.tsx'
import ThemeToggle from './ThemeToggle.tsx'
import './dev.css'

// 개발용 확인 페이지 (/dev/primitives) — Figma 「03 · Icons & Primitives」 · Dialog · Empty State와 비교해요. 데모 화면이 아니에요.

const BRANCHES = [
  { value: 'main', label: 'main' },
  { value: 'develop', label: 'develop' },
  { value: 'feat/demo', label: 'feat/demo' },
]

function PrimitivesPage() {
  const [on, setOn] = useState(true)
  const [off, setOff] = useState(false)
  const [branch, setBranch] = useState('main')
  const [tab, setTab] = useState('aws')
  const [dialogOpen, setDialogOpen] = useState(false)

  return (
    <main className="dev-page">
      <header className="dev-header">
        <h1 className="t-h1">Daisy DS · Primitives</h1>
        <ThemeToggle />
      </header>

      <section>
        <p className="t-overline t-muted">Icons · 20px</p>
        <div className="dev-inline">
          {(Object.keys(ICON_PATHS) as IconName[]).map((name) => (
            <Tooltip key={name} text={name}>
              <span tabIndex={0}>
                <Icon name={name} />
              </span>
            </Tooltip>
          ))}
          <Spinner />
        </div>
      </section>

      <section className="dev-row">
        <div className="dev-col">
          <p className="t-overline t-muted">Toggle</p>
          <div className="dev-inline">
            <Toggle label="끔 예시" checked={off} onChange={setOff} />
            <Toggle label="켬 예시" checked={on} onChange={setOn} />
          </div>
        </div>
        <div className="dev-col dev-w240">
          <p className="t-overline t-muted">Select · Select Menu</p>
          <Select label="배포 기준 브랜치" value={branch} options={BRANCHES} onChange={setBranch} leading={<Icon name="git-branch" size={16} />} />
        </div>
        <div className="dev-col dev-w320">
          <p className="t-overline t-muted">Progress Bar</p>
          <ProgressBar label="업로드 중" value={25} />
          <ProgressBar label="업로드 중" value={60} />
          <ProgressBar label="업로드 중" value={100} />
        </div>
      </section>

      <section className="dev-row">
        <div className="dev-col">
          <p className="t-overline t-muted">Tooltip (올리면 보여요)</p>
          <Tooltip text="이미지 digest가 모든 환경에서 같아요">
            <Button variant="outline">digest 3/3 일치</Button>
          </Tooltip>
        </div>
        <div className="dev-col">
          <p className="t-overline t-muted">Avatar</p>
          <div className="dev-inline">
            <Avatar type="human" name="도영" />
            <Avatar type="ai" />
            <Avatar type="human" name="도영" size="m" />
            <Avatar type="ai" size="m" />
          </div>
        </div>
        <div className="dev-col">
          <p className="t-overline t-muted">Skeleton</p>
          <div className="dev-inline">
            <Skeleton shape="line" />
            <Skeleton shape="block" />
            <Skeleton shape="circle" />
          </div>
        </div>
      </section>

      <section>
        <p className="t-overline t-muted">Tabs · Tab Item</p>
        <Tabs
          label="환경별 plan"
          value={tab}
          onChange={setTab}
          items={[
            { id: 'onprem', label: '온프레미스', env: 'onprem' },
            { id: 'aws', label: 'AWS', env: 'aws' },
            { id: 'gcp', label: 'GCP', env: 'gcp' },
          ]}
        />
      </section>

      <section className="dev-grid2">
        <Alert type="info" title="안내">배포 전에 환경변수를 확인해 주세요.</Alert>
        <Alert type="warning" title="AI 위험 예측 · 주의">RDS 인스턴스 생성에 약 5분이 걸릴 수 있어요.</Alert>
        <Alert type="danger" title="검증 실패">AWS가 3번 모두 실패해서 멈췄어요.</Alert>
        <Alert type="success" title="검증 통과">3개 환경 모두 validate · plan을 통과했어요.</Alert>
      </section>

      <section>
        <p className="t-overline t-muted">Toast</p>
        <Toast type="success" title="배포 완료" onClose={() => {}}>3개 환경 모두 정상이에요.</Toast>
        <Toast type="error" title="GCP 배포 실패" onClose={() => {}}>헬스체크 시간 초과 · 로그 보기</Toast>
        <Toast type="info" title="plan이 갱신됐어요" onClose={() => {}}>승인 대기가 길어져 plan을 다시 떴어요.</Toast>
      </section>

      <section className="dev-row">
        <div className="dev-col">
          <p className="t-overline t-muted">Dialog</p>
          <Button variant="outline" onClick={() => setDialogOpen(true)}>Dialog 열기</Button>
          <Dialog
            open={dialogOpen}
            onClose={() => setDialogOpen(false)}
            icon="rotate-ccw"
            title="v6로 롤백할까요?"
            description="온프레미스 · AWS · GCP 3개 환경이 모두 v6(9e21f0a)로 돌아가요. 확인을 위해 환경 이름을 입력해 주세요."
            actions={
              <>
                <Button variant="outline" onClick={() => setDialogOpen(false)}>취소</Button>
                <Button variant="destructive">롤백</Button>
              </>
            }
          >
            <Input placeholder="sample-monolith" />
          </Dialog>
        </div>
        <div className="dev-col dev-w480">
          <p className="t-overline t-muted">Empty State</p>
          <EmptyState
            icon="cloud"
            title="아직 배포한 프로젝트가 없어요"
            description="GitHub 레포를 연결해서 시작해 보세요"
            action={<Button variant="outline">레포 연결</Button>}
          />
        </div>
      </section>
    </main>
  )
}

export default PrimitivesPage
