# Azure 대상 허용과 환경 정보

- 근거: 승환님 전달 회의 결정, 웹 #87, 인프라 #89 답변.
- 브랜치: `server/fix-azure-target`, 최신 main `547fa8f`에서 시작했어요.

## 변경

- 기존 V1은 그대로 두고 V2에서 `ck_target_env`에 `azure`만 추가했어요.
- `tgt_demo_azure`의 환경 설명은 #89의 Container Apps·koreacentral·Azure Blob 예정 구성을 사용해요. 설명은 연결 성공을 뜻하지 않아요.
- 대상 자동 시딩은 하지 않아요. 실제 state_identity와 실행 준비가 확인되면 등록하며, ID가 다르면 표시 표도 맞춰요.

## 검증

- 로컬 임시 PostgreSQL 17.11, 루프백 포트 55491에서 운영 DB와 분리해 실행했어요.
- `DAISY_TEST_DB_URL`을 연결한 `./gradlew spotlessApply check`: 243개 통과, 실패·스킵 0개.
- 새 테스트에서 V1은 Azure 거절 → V2 적용 후 기존 3환경 보존·Azure 허용 → 알 수 없는 환경 거절 → 재적용 0건을 확인했어요.
- Azure 조회 DTO는 환경 설명을 전달하면서 연결 상태는 unknown을 유지해요.
- V1 diff 없음, `git diff --check` 통과.

## 남은 일

- PR 리뷰·머지 후 인프라가 서버 재배포와 운영 V2 적용을 진행해요.
- #89에서 실제 state_identity·대상 설정을 받은 뒤 등록하고 웹→plan→승인→apply를 검증해요.
- 이번 작업에서 운영 DB·Jenkins·클라우드 리소스는 변경하지 않았어요. #89는 전체 연결 확인 전까지 닫지 않아요.
