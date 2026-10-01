# 실행 기능 구현 작업 일지

브랜치: `server/feat-deployment-execution`. 기존 Draft PR #19의 엔티티·common 기반에서 시작한다.

## 범위

배포 접수·상태·승인·멱등성·state 충돌 제어, Jenkins 명령 전달·추적·결과 수신, 이벤트·SSE 재생, script·AI 사용량 수신, 취소·재시도·롤백 실행 서비스. 인증·관리·사용자 REST API는 은현, 실제 AI·Terraform은 인프라 영역이다.

## 진행

- 작업 전 확인: worktree는 사용자 `references/`만 untracked. PR #19 리뷰·댓글 없음. 다른 열린 백엔드 구현 PR 없음.
- 기존 PR 변경을 섞지 않도록 후속 브랜치를 생성했다. 새 브랜치 push/PR 게시·클라우드 실행은 아직 하지 않는다.
- 명세를 먼저 추가했다. 각 기능 커밋 후 이 문서에 연결·미결·검증 결과를 갱신한다.
- 전체 빌드·느린 검증은 구현 후 일괄 실행한다. 중간 커밋은 검증 완료 상태가 아니다.
- `fce4723`: 명령 저장·제출 워커, 미확인 제출 복구, 제출 직전 승인 검사, 늦은 응답의 실행 식별자 덮어쓰기 차단. 테스트 소스만 작성했으며 아직 실행하지 않았다.
- `a311d43`: 검증 script·AI 호출 수신, 원천 ID 중복/상충, 산출물 가용성, 미확인 사용량 NULL 보존. 테스트 소스만 작성했으며 아직 실행하지 않았다.
- `d38ec74`: 운영 Flyway와 분리한 실행 도메인 SQL 초안·관리 도메인 테스트 fixture 작성.
- `87fe1fa`: 접수·승인·취소·재시도·롤백·stale 재plan 실행 서비스 연결.
- `48d5370`: 인증 포트를 통한 내부 콜백과 단계·구조화 로그 수신 연결.
- `0688b94`: 독립 PostgreSQL schema의 동시 접수·승인 충돌·취소·stale 재전송 통합 테스트 작성.
- `f0e50e5`: progressive console 수집·UTF-8/줄 경계·바이트 커서 원자 저장 구현. 인프라 출력 계약 확인 전 기본 비활성.
- 별도 모델의 소스 리뷰에서 큐 취소 후 대상 종료·락 해제 누락과 완료 후 늦은 단계 시작 이벤트 노출을 발견했다. 수정·회귀 테스트를 진행하며 전체 검증 전 완료로 표시하지 않는다.
- `origin/main`의 CI/CD Jenkinsfile을 읽었다. 현재 프로토타입은 `APP_REPO`, `IMAGE_TAG`, `DEPLOY_AWS/GCP` 등의 파라미터와 Jenkins 내부 `input` 승인을 사용하며, 백엔드 request_id·구조화 콜백·승인 plan 전달은 없다. 신규 백엔드 연동 제안과 현재 Job은 바로 호환되지 않는다. 인프라 파일은 수정하지 않고 클라이언트를 기본 비활성으로 구현한다.

## 구현 중 확인한 경계

- plan은 승인 시점뿐 아니라 대기 명령의 실제 제출 직전에도 현재 revision·입력·유효 기한과 대조해야 한다. 큐 대기 중 만료된 plan을 그대로 제출하지 않도록 명령 워커에 확인을 추가한다.
- Jenkins 제출 응답과 콜백의 도착 순서는 정해져 있지 않다. 먼저 확인한 queue/build 식별자와 종료 상태를 늦은 제출 응답으로 덮지 않도록 한다.
- 로그는 구조화 콜백과 progressive console 수집을 제공한다. console은 비밀값 제거·UTF-8 byte offset 계약 확인 후 별도 활성화한다. 원문 console을 일단 저장한 뒤 삭제하는 방식은 사용하지 않는다.

## 외부 확인이 필요한 것

- 은현의 접근/입력 서비스 구현 연결, 운영 Flyway 버전·담당.
- 인프라 Job·인증·콜백/조회·request_id 복구와 승인된 plan 실행 계약.
- 선택 원문·재사용 판정·롤백 입력 복원 정책은 초안/미제공 여부를 구분한다.

## 일괄 검증에서 확인할 것

- 접수·명령·이벤트·멱등 응답의 원자 저장과 동일 요청 동시 접수.
- DB 복합 FK의 다른 프로젝트/대상 참조 차단, 같은 state의 승인 충돌, 순환 참조 저장 순서.
- 승인 당시와 제출 직전 plan 검증, 제출 후 늦은 정상 완료가 만료만으로 버려지지 않음.
- 같은 콜백 재전송 무변경, 동일 ID 다른 내용 충돌, 역순 결과의 종료 상태 되돌림 금지.
- STOP 수락과 실제 종료 구분, 여러 대상을 공유하는 run의 부분 중단 제약.
- stale 재plan의 회차 유지와 새 승인, 실패 대상만 새 배포, 롤백 입력·코드 불변.
- 재사용 확인과 AI 호출 기록의 모순 차단, 미확인 비용 NULL, 소수 정밀도.
- 콜백 인증·실행 범위·본문 제한·원문 비밀값 차단, SSE 권한 철회·재생·연결 정리.
- 실제 PostgreSQL에서 JPA 상태 갱신과 JDBC 이벤트 counter가 서로 덮이지 않음.

검증용 스키마는 독립 DB에서만 적용한다. 운영 Flyway 번호를 임의 배정하거나 은현의 관리 도메인 구현을 대신 완성한 것으로 표시하지 않는다.

## 일괄 검증 결과

2026-10-01, Java 21.0.12.1 · PostgreSQL 17.11. 기능 코드 취합 후 포맷·컴파일·단위/DB 테스트·jar 빌드를 실행했다.

- 최종 명령: `./gradlew spotlessApply check build --no-daemon --offline`.
- 최종 결과: **91 tests, 0 skipped, 0 failures, 0 errors**, `BUILD SUCCESSFUL`.
- PostgreSQL 12개 사례는 테스트마다 별도 UUID schema를 생성·정리해 실행했다. 최초 일괄 실행에서 확인된 nullable SQL 파라미터 타입과 테스트 매처/컬럼 이름 오류를 수정하고 전체를 다시 통과했다.
- 실제 Boot jar는 별도 시험 schema에서 `ddl-auto=validate` 상태로 기동했다. `/actuator/health` UP, `/v3/api-docs` 정상 응답. 콜백 기본 비활성 404, 활성화하되 인증 포트가 없으면 안전한 공통 오류 403.
- 시험 스키마는 관리 fixture + 실행 SQL 초안이다. 이 기동에서는 Flyway를 껐으며 운영 마이그레이션 검증으로 주장하지 않는다. 실제 Jenkins·클라우드·사용자 저장소에 요청하지 않았다.
- 테스트 HTML/XML은 `server/build/reports/tests/test/`와 `server/build/test-results/test/`에서 확인한다. 빌드 산출물은 git에 커밋하지 않는다.

### 범위별 완료 근거

| 승환 범위 | 구현과 검사 근거 |
|---|---|
| 접수·고정 입력·멱등성 | DeploymentExecutionService/IdempotencyService, 동일 키 동시 접수·상충 입력 DB 검사 |
| 상태·독립 진행·승인 | Deployment/Target/PlanRevision/Approval, 회차·역순·부분 결과 단위 검사, 실제 plan→승인→성공·동일 state 승인 경쟁 DB 검사 |
| 취소·stale·재시도·롤백 | 미제출/큐 취소의 종료 증거·락 해제, stale 새 명령/승인 계보, retry/rollback 불변 입력 DB 검사 |
| Jenkins 요청·복구 | JenkinsClient/CommandService/Worker, 가짜 HTTP 서버·응답 유실/STOP 구분 단위 검사, dispatching→unknown 복구 DB 검사 |
| 콜백·단계·로그 | 인증 전 본문 거절·제한/허용 범위 단위 검사, 단계 occurrence 순서·소요 시간 검사, 실제 HTTP 인증 미연결 거절 |
| 이벤트·SSE | EventJournal/EventSseService, seq와 상태 원자 rollback DB 검사, 재생·stale 생략·권한 철회·heartbeat/resync·연결 정리 단위 검사 |
| console | 단일 run owner·UTF-8/줄/byte 범위 단위 검사, 강제 DB 오류의 event/seq/cursor 원자 rollback·재전송 DB 검사 |
| script·사용량 | 원천 ID 중복/상충·만료·비밀값/필드 검사, 실제 늦은 NULL 사용량 저장 및 배포 상태 보존 |
| 담당자 인계 | execution-service-contract.md의 호출·입력/인가 포트·응답 규칙, Jenkins transport/callback/console 문서, README 검증 방법 |

### 남은 연결과 한계

승환의 이번 실행 서비스 구현·로컬 검증과 팀 서비스 전체 출시 준비는 다르다. 은현의 사용자 인증·프로젝트/대상 입력 포트·조회/REST/SSE 엔드포인트, 운영 Flyway 조율, 인프라 Job의 request_id·콜백·승인 plan 실행·로그 계약 확인이 필요하다. 웹·앱·실제 Jenkins의 전체 흐름, 프록시/SSE 전달, 실제 산출물 접근 권한은 아직 통합 검증하지 않았다.

기본 비활성 설정과 미연결 권한 거절을 유지한다. 새 의존성·실제 Terraform/Claude 실행·상대 영역의 가짜 허용 구현은 추가하지 않았다. push·새 PR 게시도 하지 않았다.
