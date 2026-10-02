# 성공 결과의 현재 배포·연결 상태 반영

2026-10-02 · 김승환 · `server/feat-target-observation`

후속 전체 API 검사에서 조회 누락과 OpenAPI 불일치를 추가 확인했어요. 이 문서의 성공 흐름 통과를 백엔드 전체 완료로 해석하지 않아요. 최신 항목별 결과는 [전체 API 점검](2026-10-02-backend-api-audit.md)을 봐주세요.

## 바꾼 것

인프라에서 성공 콜백까지 보냈지만 A-02의 현재 배포가 비어 있었어요. 결과 저장과 별개로 `target.current_deployment_target_id`를 쓰는 코드가 없었어요.

`DeploymentExecutionService.acceptState`의 기존 성공 검증 뒤에 현재 포인터와 연결 확인을 기록하도록 연결했어요. `DeploymentStore`에서 관측 필드 네 개만 갱신하고, 새 테이블·의존성·공개 API는 추가하지 않았어요.

- 현재 execution·sequence·plan·입력·이미지 검증을 그대로 거쳐요.
- 프로젝트 락 → 대상 결과 저장 → 현재 포인터·연결 확인 → state 락 해제 → 커밋 순서예요. 상태·이벤트·포인터 중 일부만 남지 않아요.
- 해당 실행의 state 락이 있어야 해요. 활성 프로젝트·대상의 state 주소·설정 revision·자격증명 참조/버전도 고정 입력과 같아야 해요.
- 실패·취소·unknown·중복·늦은 결과는 포인터를 바꾸지 않아요. 새 롤백 배포도 승인한 plan 적용에 성공해야 현재가 돼요.
- DB에는 기존 값 `connected`를 써요. 공개 조회의 기존 매핑이 `ok`로 반환해요. 확인 시각은 서버가 성공을 수신한 시각이며, 지속적인 헬스체크 결과가 아니에요.

## 담당 경계

승환 지시에 따라 성공 관측 필드의 갱신 주체를 실행부로 정했어요. `AGENTS.md`와 실행 서비스 계약에 기록했어요. 대상 설정 관리와 공개 DTO는 은현님 영역으로 유지했어요.

은현님께는 PR에서 다음을 공유해요.

- `current_deployment_target_id`, `connection_state`, `connection_checked_at`, `updated_at`은 이번 실행부에서 함께 기록해요. 별도 갱신 서비스를 추가하지 않아도 돼요.
- 인프라 요청 1번(현재 배포)·3번(연결 확인)에 해당해요. 2번 URL·digest·health 응답 연결과 4번 WR-04 정보 조회는 이 PR에서 건드리지 않았어요.
- `observed_state`·`observed_at`은 별도 실제 관측 필드라 추정값을 넣지 않았어요.

## 검증

운영 DB가 아닌 로컬 PostgreSQL 17 테스트 DB를 사용했어요. 테스트마다 독립 스키마에 Flyway를 적용하고 Spring/JPA validate를 거쳐요. 실제 Jenkins 워커·클라우드는 실행하지 않았어요.

```sh
./gradlew spotlessCheck check build --rerun-tasks --no-daemon --offline
```

Java 21 및 `DAISY_TEST_DB_*` 설정으로 실행했어요. 결과: **BUILD SUCCESSFUL, 236개 테스트, 실패·오류·건너뜀 0개**예요. 기존 서버 전체 테스트를 포함한 수치이고, 새 테스트는 8개예요. 기존 성공·롤백 테스트에도 검증을 추가했어요.

- 성공 직후 A-02 내부 `currentByTarget`이 `confirmed`와 해당 배포를 반환해요.
- 같은 성공 동시 수신·재전송, 다음 성공 후 옛 실행 보고가 현재를 덮지 않아요.
- 전체 트랜잭션 롤백 시 대상 상태·포인터·연결 확인·락이 함께 복원돼요. 이후 동일 콜백으로 정상 반영돼요.
- 설정 revision·state 주소·자격증명 참조/버전 변경, 프로젝트·대상 연결 해제, state 락 부재에서는 성공 이력만 남고 현재 포인터는 바뀌지 않아요.
- 승인된 롤백의 성공 후에는 원본이 아닌 새 롤백 배포 대상이 현재가 돼요.
- 갱신 호출을 제거한 대조 실행에서는 `realCreateBuildPlanApproveSuccessAndTerminalReplayAreAtomic`이 현재 포인터 NULL로 실패했어요. 호출 복원 후 전체 236개를 다시 통과했어요.

## 남은 일

리뷰·머지 후 개발 서버에 반영하고 새 성공 콜백으로 웹·앱의 현재 배포와 연결 표시를 확인해야 해요. 기존 종료 배포를 시각순으로 골라 소급 보정하지 않아요. 아래 서버 통합 검증은 완료했고, 실제 클라우드·전체 화면 검증은 후속이에요.

## #84 통합과 최종 서버 연결 검증

- #84 HEAD `988e7ef`를 직접 PostgreSQL 포함 빌드·테스트로 확인한 뒤 사용자 요청대로 코멘트·승인·Squash 머지했어요. `b5a0e62`를 현재 브랜치로 합쳤고 충돌은 없었어요.
- `AiUsageService`의 `external_call_id`에만 `#`를 추가 허용했어요. `daisy-cd-plan#18/aws/ai-1`을 변형 없이 저장해요. provider·model·내부 ID 검증, 길이·제어 문자·비밀값 차단은 유지해요.
- 통합 후 `spotlessApply check build --rerun-tasks --no-daemon --offline`: **241개, 실패·오류·건너뜀 0개**예요.
- [반복 실행 가능한 검증 스크립트](../../scripts/verify-result-flow.py)를 남겼어요. Java 21, PostgreSQL 17, Python 표준 라이브러리와 `psql`만 사용해요. 매 실행마다 새 스키마·임의 포트·일회용 인증값을 쓰고 종료 시 검증 서버와 해당 스키마를 정리해요. 운영 DB는 건드리지 않아요.

실제 jar의 HTTP 요청으로 다음을 확인했어요.

1. 로그인과 배포 접수 201, 같은 키 재전송 시 같은 배포예요.
2. `#` 포함 AI 사용량 콜백 200, 동일 콜백은 같은 ACK, 같은 ID의 다른 값은 409예요. 실패 호출의 미확인 토큰은 null이며 `unknown_calls`에 포함돼요.
3. plan 콜백 → A-04의 승인 목록 → 승인 202, 동일 승인 재전송에도 apply 명령은 한 건이에요.
4. 성공 콜백 → 결과·현재 포인터·연결 상태 반영 → A-02 `confirmed/ok`, A-04 URL·digest, WR-04 환경 정보와 연결 상태가 조회돼요. 중복 성공은 확인 시각을 바꾸지 않고 종료 후 state 락은 0건이에요.
5. AI 사용량 상세·합계와 저장된 SSE 재생 ID를 확인했어요. Bearer 없이 배포 상세를 조회하면 401이에요.

**검증의 경계:** 서버 API·인증·서비스·PostgreSQL은 실제 코드예요. 프로젝트/빌드는 테스트 시드이고 Jenkins 제출 상태와 Terraform 산출물은 `MOCK`으로 표시한 입력이에요. 실제 Jenkins·클라우드·브라우저를 실행한 결과는 아니에요.

초기 스크립트에서 데모 대상 중복 시드, 계정 시딩 전 로그인, 생성 응답 202 가정을 고쳤어요. 제품 오류로 처리하지 않았으며 최종 재실행은 전 구간 통과했어요.
