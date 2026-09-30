import Button from '../../components/Button.tsx'
import Dialog from '../../components/Dialog.tsx'
import Icon from '../../components/Icon.tsx'
import InfoRow from '../../components/InfoRow.tsx'

// W-14 앱 설치 — 사이드바 "Mac 앱 받기" · 로그인 폼 아래 링크에서 열어요
// 설치는 TestFlight 공개 링크 하나로 (iPhone · Mac 공용). 외부 테스트 심사 전이라 링크를 열어도 아직 빌드가 없을 수 있어요
// 버전 · 지원 OS · 공증 여부는 승준 님과 결정 [미정]
const TESTFLIGHT_URL = 'https://testflight.apple.com/join/wF5sjQPG'

type MacAppDialogProps = {
  open: boolean
  onClose: () => void
}

function MacAppDialog({ open, onClose }: MacAppDialogProps) {
  return (
    <Dialog
      open={open}
      onClose={onClose}
      icon="download"
      title="앱으로 승인 알림 받기"
      description="승인이 필요할 때 Mac · iPhone 알림으로 바로 알려줘요. 승인 · 상태 확인은 앱에서, 전체 배포 흐름은 웹에서 진행해요."
      actions={
        <>
          <Button variant="outline" onClick={onClose}>
            닫기
          </Button>
          <Button variant="secondary" trailing={<Icon name="external-link" size={16} />} onClick={() => window.open(TESTFLIGHT_URL, '_blank', 'noopener')}>
            TestFlight로 설치
          </Button>
        </>
      }
    >
      <div>
        <InfoRow label="설치">
          <a href={TESTFLIGHT_URL} target="_blank" rel="noopener noreferrer">
            testflight.apple.com/join/wF5sjQPG
          </a>
        </InfoRow>
        <InfoRow label="버전">v0.1.0 · [미정]</InfoRow>
        <InfoRow label="지원">iOS 17 · macOS 14 이상</InfoRow>
      </div>
      <p className="t-body-sm t-muted">
        TestFlight 앱을 먼저 설치한 뒤 링크를 열어요. 외부 테스트 심사가 끝나기 전에는 설치할 빌드가 보이지 않을 수 있어요.
      </p>
    </Dialog>
  )
}

export default MacAppDialog
