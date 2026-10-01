# 은현 API 연결용 배포 조회 서비스 (2026-10-01)

## 변경

`DeploymentQueryService` 한 개에 current·deployedTo 두 배치 조회와 내부 DTO를 구현했습니다. 관리 Repository·Entity는 건드리지 않고 공개 API도 추가하지 않았습니다. V1 변경이나 새 테이블은 없습니다.

- current: 관리가 넘긴 현재 포인터의 프로젝트·대상 소속을 대조하고 성공 배포·고정 이미지 정보를 반환합니다. 최신 성공을 임의 선택하지 않습니다. 포인터 NULL은 실제 인프라 부재와 다릅니다.
- deployedTo: 정확한 source_version_id·대상별 마지막 성공 1건입니다. 부분 성공의 성공 대상 포함, 실패/진행 중 제외, 같은 commit 재빌드 분리, 동률 정렬 고정.
- 공통: ExecutionAccess.requireRead, 포트 누락 거절, 최대 100개 배치·중복/빈 ID 검사, 읽기 트랜잭션·바인딩 SQL, 불변 DTO/목록. secret/plan/snapshot 원문 노출 없음.

## 검증

Java 21·PostgreSQL 17.11의 독립 DB에서 `spotlessApply check build --rerun-tasks --no-daemon --offline` 성공. 기존 125개에 단위 2개·실DB 3개를 추가해 **130 tests, 0 skipped/failures/errors**, 실DB 17개를 확인했습니다. 실행 중인 개발 DB 대신 기존 전용 시험 DB를 사용했고 검사 후 Postgres를 종료했습니다.

- 현재 포인터가 더 오래된 성공을 가리킬 때 최신 성공·최신 실패로 바뀌지 않음, MSA 이미지·digest 보존, NULL 포인터와 실패 포인터 처리, 조회가 포인터/명령/이벤트를 변경하지 않음.
- 빌드별·대상별 성공 이력, 부분 성공 포함, 실패·진행 중 제외, 같은 commit 재빌드 구분, 성공 이력 없음, 같은 완료 시각의 결정적 정렬.
- 교차 프로젝트/다른 대상 포인터 거절, 외부 빌드 정보 비노출, 권한 철회·포트 누락 거절, 중복/빈 ID·배치 제한.

실DB 조회 테스트는 명시된 MOCK 이력 fixture를 사용합니다. 실제 인프라 배포/관측 검증이 아니며 기존 테스트의 관리 인가 포트 역시 대역입니다. 은현의 운영 어댑터 연결 후 같은 시나리오를 다시 확인해야 합니다.

## 은현님 연결 위치와 후속

`docs/execution-service-contract.md`의 **은현 조회 API에 연결할 서비스**에 실제 호출 예시·입력·반환·오류·이미지 매핑을 적었습니다. A-02 대상 목록에서 관리 소유 current 포인터를 전달하고, A-06 빌드 페이지에서 source ID 목록을 전달하면 됩니다. 공개 DTO 변환은 은현이 진행합니다.

아직 하지 않은 것: ExecutionAccess 운영 어댑터, 공개 REST 연결, target의 실제 관측/현재 포인터 갱신, 실제 Jenkins 결과 수신. 포인터가 아직 NULL이면 이 조회만 추가해도 current가 채워지는 것은 아닙니다. 잘못된 현재 버전을 만들지 않도록 관측 갱신 계약은 별도 후속으로 유지합니다.

이번 작업은 로컬 기능 커밋까지 진행하며, #40 push·은현님 댓글 공유는 아직 하지 않았습니다.
