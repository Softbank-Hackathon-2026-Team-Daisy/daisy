# 실행 스키마 초안과 독립 PostgreSQL 검증

[sql/execution.sql](sql/execution.sql)은 승환 소유 12개 테이블의 실행 가능한 검토 초안이다. Flyway 자동 검색 경로 밖에 두며 운영 마이그레이션 번호를 예약하거나 적용하지 않는다. 은현의 account/project/project_member/target/source_version 테이블 정의·인가 정책은 변경하지 않는다.

통합 검증은 테스트 전용 `db/managed-domain-fixture.sql`의 관리 테이블 5개, 같은 실행 SQL, `db/managed-domain-links.sql`의 관리 target 현재 포인터 FK 순서로 적재한다. 전체 스키마 사본을 별도로 유지하지 않는다. 관리 fixture는 엔티티와 설계안의 타입·키를 재현한 테스트 대역이며 운영 관리 DDL을 대신하지 않는다. account 역할 목록은 은현이 확정하므로 fixture에 임의 CHECK를 두지 않는다.

DDL은 PK·복합 소속 FK·CHECK·부분 UNIQUE·기본값·조회 인덱스를 포함한다. nullable 순환 포인터는 테이블 생성 후 FK를 붙이고 서비스가 마지막에 연결한다. 삭제 CASCADE·TTL은 없으며 PK/UNIQUE의 선두 컬럼으로 충분한 중복 조회 인덱스를 추가하지 않는다. plan active·approval pending·run 콘솔 owner·source offset·프로젝트 투영의 부분 UNIQUE를 유지한다.

DB가 검사할 수 없는 조건은 서비스 책임이다: current plan active, 승인 만료가 plan 기한 이하, apply digest/input 일치, state lock과 대상 snapshot 일치, lineage 부모 일치, reused와 실제 AI 사용량 충돌, source 입력 불변성. CHECK에서 다른 테이블을 조회하거나 DB FK만으로 인증·인가를 구현하지 않는다.

통합 테스트는 `DAISY_TEST_DB_URL`이 설정된 경우에만 실행한다. `DAISY_TEST_DB_USER`·`DAISY_TEST_DB_PASSWORD`로 제공된 연결에 임의 UUID의 전용 schema를 생성하고 해당 search_path에서만 작업한다. 테스트 종료 시 자신이 생성한 schema만 정리하며 public·DB 전체를 지우지 않는다. 운영 DB 사용을 지시하는 문서가 아니다.

현재 단계에서는 SQL·테스트 소스만 작성한다. 사용자 요청대로 PostgreSQL 실행·빌드·테스트·포맷은 기능 취합 후 별도로 수행하며, 아직 DB 적용 성공이나 전체 실행 흐름 검증 완료를 주장하지 않는다.
