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

## PR #19 기반 통합과 차이 점검 (2026-10-01)

- 사용자 요청으로 기존 기능 브랜치로 복귀하고 `server/feat-deployment-domain`의 `d3a243a`를 `55c1d11`로 merge했다. 충돌 없이 기존 기능 커밋을 보존했다. #19의 main 머지·기능 브랜치 push는 수행하지 않았다.
- DB 테스트가 예전 SQL 초안·관리 fixture를 사용하던 것을 정식 `classpath:db/migration`의 Flyway 적용으로 전환했다. 테스트 계정만 `admin`에서 합의된 `owner`로 변경했다. 업무 코드·V1은 그대로다.
- PostgreSQL 17.11의 별도 빈 DB에서 **93 tests, 0 skipped/failures/errors**. 실DB 12건은 매번 전용 schema에 V1을 적용하고 JPA validate·실행/승인/락/멱등/수신 시나리오를 검사했다. `spotlessApply check build --no-daemon --offline` 통과, 검사용 DB 종료. 실제 Jenkins는 호출하지 않았다.

### 다음 기능 수정 목록 — 이번에는 진단만

| 부분 | 현재 코드와 최신 방향의 차이 | 다음 작업 |
|---|---|---|
| 빌드 선택 | CreateRequest·ExecutionInputs.capture가 commitSha만 받고 source_version_id는 관리 포트 결과로 받음 | 명시적으로 선택한 빌드 ID를 요청·멱등 hash·소속 검증에 연결. 은현 입력 포트와 함께 변경 |
| apply 중단 | cancel은 이미 제출한 apply에도 stop 명령을 만들고 JenkinsWorker가 build stop을 호출할 수 있음 | #32 합의대로 apply 시작 후 요청 기록만 유지하고 STOP 전달 차단. prepare/queue 취소는 지원 범위 별도 확인 |
| 다중 승인·삭제 확인 | 선택한 대상만 원자 처리하고 확인 문구는 target snapshot의 name과 비교 | 최신 S4 안과 대조: 승인 대기 전체 집합 검증·프로젝트명 고정 문구·소비자 DTO 연결. 최종 계약 확인 후 변경 |
| 롤백 | RollbackRequest에 target_ids·사용자 reason이 없고 성공 원본의 모든 대상을 복제 | 선택 대상·사유를 요청/hash/이벤트에 연결. 원본 실행 입력은 보존 |
| Jenkins 전송·결과 | request_id/payload form과 구조화 callback 중심의 초기 계약. 현재 실제 Job 파라미터·산출물 폴링과 다름 | #35 답변에 따라 plan/apply 파라미터·결과 adapter 연결. 확인 전 기본 비활성 유지 |
| SSE 선택 필터 | openDeployment/openProject에 event_type 필터가 없음 | 필터 계약 확정 후 채널 seq를 그대로 유지하면서 추가 |

테스트 통과는 현재 구현과 V1의 호환성을 확인한 것이며 위 계약 차이가 해소됐다는 의미는 아니다. API 표시(attempt null·image digest·사용량 합계)는 은현 조회 DTO와 맞춘다. 이전 실행 문서의 Jenkins 내부 승인·콜백 중심 설명은 현재 인프라 사실로 사용하지 말고 #19/#35를 우선한다.

## 최신 계약 차이 수정 (2026-10-01)

사용자의 후속 수정 요청으로 위 목록 중 서버가 구현할 수 있는 동작을 반영했다. 신규 테이블·V1 변경·외부 배포 실행은 하지 않았다.

- `CreateRequest`와 관리 포트의 선택 키를 sourceVersionId로 변경했다. 반환된 성공 빌드 ID 일치 검사 후 commit·이미지를 고정하고 선택 ID를 멱등 hash에 포함한다. 같은 commit의 재빌드 두 건 선택과 옛 빌드 수신 차단을 실DB에서 검사했다.
- 승인 대기 전체 집합과 approval_id를 확인하고 전부 같은 승인/거절 결정을 원자 처리한다. pending 생성 시 `ExecutionInputs.projectName`으로 프로젝트 이름을 고정하며 삭제 확인·Jenkins 제출 전 검사에 같은 의미를 적용했다. 프로젝트 이름 변경 뒤 기존 문구 유지, 누락·stale 승인 때 전체 rollback을 검사했다.
- 미제출 전체 명령은 취소할 수 있지만 공유 pending 명령의 일부 대상만 취소하면 409다. 이미 제출되었거나 불명확한 apply는 선택 대상의 요청자·시각만 기록하며 STOP·상태 종료·락 해제가 없다. 명령 서비스도 apply STOP을 거절하고 워커는 과거 apply STOP까지 차단한다. plan STOP은 `daisy.jenkins.plan-stop-confirmed` 기본 false로 인프라 확인 전 외부 호출을 막는다.
- 롤백은 전체 성공 원본에서 선택한 대상만 복원한다. 사유(필수·최대 1000자·비밀값 거절)와 선택 대상을 요청 hash에 포함하고 사유는 생성 이벤트, 대상·원본은 lineage 행에 기록한다. 이벤트에 임의 요청 객체를 허용하거나 실행 입력을 변형하지 않는다. 같은 키로 대상/사유를 바꾸면 409이며 원본은 변하지 않는다.
- SSE의 선택적 단일 eventType 필터를 추가했다. 제외한 사건은 내부 cursor만 전진하며 전송 ID는 원래 seq다. heartbeat/resync와 권한 검사·재연결 규칙은 유지한다. 기존 필터 없는 호출도 유지한다.
- Jenkins Job 기본명은 확인된 daisy-cd-plan/apply로 매핑했다. **#35 답변은 아직 없으며 기존 request_id/payload 전송·구조화 callback을 실제 Job 계약으로 간주하지 않는다.** 실제 파라미터 adapter·산출물 폴링 연결·대상/승인 집합 대조는 남아 있다. 기본 비활성은 유지했다.

### 연결 담당자에게 전달할 변경

은현 구현의 `ExecutionInputs.capture`는 선택 빌드 ID의 프로젝트 소속·성공 상태를 검사한 BuildInput을 반드시 반환해야 한다. 새 `projectName(projectId)`도 같은 트랜잭션에서 제공한다. 사용자 API는 단일 삭제 확인 문구를 대상별 내부 Decision에 동일하게 전달하고, 롤백의 선택 대상·사유를 새 요청 인자에 연결한다. 공개 DTO·OpenAPI와 인프라 파일은 이번 작업에서 수정하지 않았다.

### 검증

Java 21·PostgreSQL 17.11의 독립 DB에서 `spotlessApply check build --no-daemon --offline` 실행. 정식 Flyway V1을 사용하는 실DB 테스트 14개를 포함해 전체 99개 통과, skip/failure/error 0. 테스트는 새 schema만 생성·정리하며 관리/인가 포트는 표시된 테스트 대역이다. 실제 Jenkins·클라우드·실제 인증·웹/앱 E2E는 미검증이다. 기능 브랜치는 로컬 커밋으로 유지하고 push·새 PR 게시를 하지 않는다.
