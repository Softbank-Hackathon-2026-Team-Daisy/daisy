import Button from '../../components/Button.tsx'
import Dialog from '../../components/Dialog.tsx'
import Icon from '../../components/Icon.tsx'
import InfoRow from '../../components/InfoRow.tsx'

// W-14 앱 설치 — 사이드바 "Mac 앱 받기" · 로그인 폼 아래 링크에서 열어요
// Mac: GitHub Releases의 .dmg (Developer ID 서명 + Apple 공증), iPhone: TestFlight 공개 링크 (베타 심사 뒤 열려요)
// Mac은 고정 주소 mac-latest/Unibloom.dmg가 (레포 unibloom, 10/1 #39) 늘 최신 빌드를 가리켜서, 새 빌드가 나와도 웹은 안 바꿔도 돼요 (승준 님 결정 9/30 20:32)
const MAC_APP = {
  file: 'Unibloom.dmg',
  minOs: 'macOS 15 (Sequoia) 이상',
  url: 'https://github.com/Softbank-Hackathon-2026-Team-Daisy/unibloom/releases/download/mac-latest/Unibloom.dmg',
}
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
      title="Mac 앱으로 승인 알림 받기"
      description="승인이 필요할 때 Mac 알림으로 바로 알려줘요. 승인 · 상태 확인은 앱에서, 전체 배포 흐름은 웹에서 진행해요."
      actions={
        <>
          <Button variant="outline" onClick={onClose}>
            닫기
          </Button>
          <Button variant="secondary" onClick={() => window.open(MAC_APP.url, '_blank', 'noopener')}>
            Mac 앱 다운로드 (.dmg)
          </Button>
        </>
      }
    >
      <div>
        <InfoRow label="파일">{`${MAC_APP.file} · 최신 버전`}</InfoRow>
        <InfoRow label="지원">{MAC_APP.minOs}</InfoRow>
        <InfoRow label="iPhone">
          <a href={TESTFLIGHT_URL} target="_blank" rel="noopener noreferrer" style={{ display: 'inline-flex', alignItems: 'center', gap: 'var(--space-1)' }}>
            TestFlight로 설치
            <Icon name="external-link" size={14} />
          </a>
        </InfoRow>
      </div>
      <p className="t-body-sm t-muted">Apple 공증을 받은 앱이라 바로 열려요. iPhone TestFlight 링크는 베타 심사가 끝난 뒤 열려요.</p>
    </Dialog>
  )
}

export default MacAppDialog
