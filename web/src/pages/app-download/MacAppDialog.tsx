import Button from '../../components/Button.tsx'
import Dialog from '../../components/Dialog.tsx'

// W-14 Mac 앱 다운로드. 파일 호스팅 위치 · 버전 · 용량은 승준 님과 결정 [미정] (SPEC.md §2-3)
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
      title="Mac 앱 받기"
      description="배포 진행과 승인을 Mac 앱에서도 볼 수 있어요. 파일 위치가 정해지면 다운로드를 열어요."
      actions={
        <>
          <Button variant="outline" onClick={onClose}>
            닫기
          </Button>
          <Button variant="secondary" disabled>
            다운로드 (준비 중)
          </Button>
        </>
      }
    />
  )
}

export default MacAppDialog
