# 실행 스키마와 독립 PostgreSQL 검증

[sql/execution.sql](sql/execution.sql)은 V1 합의 전 승환 소유 12개 테이블의 검토 초안이다. **현재 스키마 기준은 `src/main/resources/db/migration/V1__init.sql`이며 테스트도 Flyway로 이 파일을 적용한다.** 초안과 관리 fixture는 과거 검토 자료로 남기며 현재 테스트·기동에 적용하지 않는다.

통합 검증은 테스트마다 생성한 전용 schema에 `classpath:db/migration`을 적용한다. 테스트 계정은 V1의 `owner/viewer` 제약에 맞춰 `owner`로 생성한다. 관리·인가 서비스 대역은 그대로이므로 실제 인증 통합을 검증했다는 뜻은 아니다.

DDL은 PK·복합 소속 FK·CHECK·부분 UNIQUE·기본값·조회 인덱스를 포함한다. nullable 순환 포인터는 테이블 생성 후 FK를 붙이고 서비스가 마지막에 연결한다. 삭제 CASCADE·TTL은 없으며 PK/UNIQUE의 선두 컬럼으로 충분한 중복 조회 인덱스를 추가하지 않는다. plan active·approval pending·run 콘솔 owner·source offset·프로젝트 투영의 부분 UNIQUE를 유지한다.

DB가 검사할 수 없는 조건은 서비스 책임이다: current plan active, 승인 만료가 plan 기한 이하, apply digest/input 일치, state lock과 대상 snapshot 일치, lineage 부모 일치, reused와 실제 AI 사용량 충돌, source 입력 불변성. CHECK에서 다른 테이블을 조회하거나 DB FK만으로 인증·인가를 구현하지 않는다.

통합 테스트는 `DAISY_TEST_DB_URL`이 설정된 경우에만 실행한다. `DAISY_TEST_DB_USER`·`DAISY_TEST_DB_PASSWORD`로 제공된 연결에 임의 UUID의 전용 schema를 생성하고 해당 search_path에서만 작업한다. 테스트 종료 시 자신이 생성한 schema만 정리하며 public·DB 전체를 지우지 않는다. 운영 DB 사용을 지시하는 문서가 아니다.

`ExecutionPostgresTest`는 schema 적재 후 Boot/JPA의 `ddl-auto=validate`로 17개 엔티티를 대조하고 실제 실행·명령·journal·멱등·script·usage 서비스를 연결한다. 검증 대상으로 같은 키 동시 생성, source 연결→plan→승인→apply→성공, 중복/상충 수신, terminal 후 NULL 사용량, 같은 state 승인 경쟁의 전체 롤백, JPA flush와 JDBC seq 유지, 이벤트·상태·counter 원자 롤백, 교차 프로젝트 복합 FK 거절을 작성했다. 테스트 전용 관리/인가 포트는 `MOCK`으로 표시하며 Jenkins worker·HTTP client·외부 호출은 등록하지 않는다. 각 연결에는 statement/lock timeout을 설정한다.

추가 검증 항목은 승인 후 APPLY 소유자로 바뀐 대상에 원래 plan 사건을 재전송해 seq·승인을 유지하는 것, 아직 전송하지 않은 APPLY 취소의 command-target 실제 종료 기록·증거·락 해제, 미적용/실행 종료가 확인된 stale 결과의 새 REPLAN 생성·회차 유지·원래 승인 결정 보존이다. stale 결과 재전송으로 명령과 seq가 늘지 않는 것도 검사한다.

2026-10-01 기능 취합 후 독립 PostgreSQL 17.11에서 위 사례를 실행했다. console 소유권·UTF-8 EOF·커서 갱신 실패 시 이벤트/seq rollback, 확정 큐 취소의 락 해제, 재시도·롤백의 고정 입력/계보, 중단된 제출 복구까지 **DB 통합 테스트 12개 통과**했다. 전체 테스트는 91개, skipped/failure/error 모두 0이다. `spotlessApply check build --no-daemon --offline`도 성공했다.

별도 시험 schema에서 실제 Boot jar의 JPA 검증·기동·health UP을 확인했다. 관리 fixture를 사용하고 Flyway를 끈 시험이므로 운영 Flyway 적용이나 은현의 실제 인증·관리 코드 통합 성공을 의미하지 않는다. 실제 Jenkins·클라우드는 호출하지 않았다.

## PR #19 통합 후 재검증 (2026-10-01)

위 91건·fixture 기동 기록은 통합 전 이력이다. `55c1d11`로 #19의 `d3a243a`까지 합친 뒤, 통합 테스트를 정식 Flyway V1 적용으로 전환했다. 독립 PostgreSQL 17.11에서 전체 **93건(실DB 12건 포함), 실패·오류·skip 0**, `spotlessApply check build --no-daemon --offline` 통과. 각 테스트는 Flyway 적용 후 JPA validate와 기존 서비스 시나리오를 검사했다. 검사용 DB 프로세스는 종료했다. V1·엔티티·업무 동작은 변경하지 않았으며, 실제 Jenkins·인증 연동 검증은 여전히 별도다.
