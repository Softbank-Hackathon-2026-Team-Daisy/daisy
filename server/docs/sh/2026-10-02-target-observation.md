# 성공 결과의 현재 배포·연결 상태 반영

2026-10-02 · 김승환 · `server/feat-target-observation`

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

리뷰·머지 후 개발 서버에 반영하고 새 성공 콜백으로 웹·앱의 현재 배포와 연결 표시를 확인해야 해요. 기존 종료 배포를 시각순으로 골라 소급 보정하지 않아요. 은현님의 결과 조회 작업과 합친 실제 전체 화면 검증은 후속이에요.
