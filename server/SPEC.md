# 서버 개발 명세

개발할 범위와 동작을 이 문서에 먼저 적고, 구현·검증 후 PR로 공유합니다.
현재 상태(2026-10-01): #32의 V1 마이그레이션과 #19 피드백 수정 커밋을 로컬에서 통합했습니다. 아래 날짜별 기록의 마이그레이션 미포함·기동 제한은 당시 범위이며 현재 상태가 아닙니다. 서버 간 계약의 답변안과 항목별 처리 상태는 [#19 정리](docs/sh/2026-10-01-pr19-feedback.md#통합-후-피드백-처리표)를 따릅니다. 합의 전 답변안을 최종 OpenAPI로 취급하지 않습니다.
기존 팀 규칙과 컨벤션은 [AGENTS.md](AGENTS.md), 실행 방법은 [README.md](README.md)를 따릅니다. Jenkins CI/CD·AI·Terraform 실행은 인프라, 실행 규칙·추적·수신은 승환, 인증·인가·관리·공개 API·조회는 은현 담당입니다. 외부 계약의 미결과 실제 구현 범위는 구분합니다.

## 실행 기능 구현 2026-10-01

### PR #19 후속 계약 반영

사용자 수정 요청에 따라 기존 실행 브랜치에 다음을 반영한다. 공개 REST/OpenAPI는 은현의 연결 범위이며, 실제 Jenkins wire protocol은 #35 답변 전까지 미연결이다.

- 배포 생성은 source_version_id를 필수 선택하고 관리 포트가 같은 프로젝트의 성공 빌드를 반환한다. commit·이미지는 그 빌드에서 도출한다. 선택 ID를 멱등 hash에 포함하고 뒤늦은 다른 빌드 수신으로 덮어쓰지 않는다.
- 승인 대기 대상 전체·대상별 approval_id를 하나의 결정으로 처리한다. 누락·추가·옛 승인·불일치 snapshot은 전체 409. pending 생성 시 프로젝트 이름을 approval.confirmation_text에 고정하고 삭제 확인값과 비교한다. 제출 직전 SQL 검사도 같은 의미를 따른다.
- apply가 외부에 제출됐거나 제출 여부가 불명확하면 취소 요청자·시각만 기록한다. STOP 생성과 워커의 기존 apply STOP 실행을 모두 차단한다. 미제출 전체 명령은 안전하게 취소하며 plan stop은 명시적인 인프라 확인 설정 전까지 비활성이다.
- 롤백은 전체 성공 배포에서 선택한 target_ids만 복원한다. reason(필수, 최대 1000자, 비밀값 제외)·대상을 멱등 hash에 포함하고 사유는 생성 이벤트, 원본·대상은 lineage에 기록한다. 고정 실행 입력은 수정하지 않는다.
- SSE에 선택적인 단일 event_type 필터를 추가한다. 원래 seq와 조회 cursor를 유지하며 heartbeat/resync는 필터링하지 않는다.
- Job 기본 매핑은 prepare/replan → daisy-cd-plan, apply → daisy-cd-apply. 기존 request_id/payload adapter와 실제 Job 파라미터는 아직 달라 활성화하지 않는다. #35에서 승인 대상·단일 APPROVAL_ID·digest/입력·결과 형식을 확인한 뒤 연결한다.
- V1·DB 구조 변경 없이 검증한다. 호출 계약과 현재 검증 근거는 [실행 서비스 계약](docs/execution-service-contract.md)·[작업 일지](docs/sh/2026-10-01-execution.md)에 기록한다.

사용자 승인 범위는 김승환의 실행 서비스·Jenkins 연결·승인·이벤트·SSE·사용량 수신이다. `server/feat-deployment-execution`에서 기존 ERD/엔티티 초안 위에 구현한다. 아래는 구현 목표이며 완료 표시는 검증 후 작업 일지에 남긴다.

- 배포 접수: 인증된 actor의 프로젝트 접근을 소유 서비스로 재검사하고, 커밋·대상·입력을 고정한다. 멱등 응답과 최초 prepare 명령은 배포 생성과 같은 트랜잭션으로 저장한다.
- 상태·승인: 대상별 독립 진행, 전체 결과 집계, 최초 생성 포함 총 3회, stale 재plan에서는 회차 유지. 현재 plan·입력·digest·만료·삭제 확인값을 검사한 승인만 apply 명령을 만든다.
- 재시도·롤백·중단: 실패 대상 새 배포, 성공 원본의 고정 입력에 근거한 롤백 초안, STOP 요청과 실제 종료 구분. 미실행이 확인되지 않은 명령은 자동 재제출·락 해제하지 않는다.
- Jenkins: 주소·인증·Job을 설정으로 공급한다. 외부 HTTP는 DB 트랜잭션 밖에서 실행하며 큐·run 추적과 응답 유실 확인을 분리한다. 인프라 미합의 프로토콜은 제안으로 문서화하고 테스트 대역으로 검증한다. 기본 상태에서 외부 작업을 자동 실행하지 않는다.
- 수신: 인증·소속·payload 제한을 확인하고 사건/호출 중복과 상충을 구별한다. 오래된 상태 사건은 기록하되 상태를 되돌리지 않고 독립 사용량은 늦게 도착해도 수용한다. 로그·산출물에 원문 secret·tfplan·tfstate를 보관하지 않는다.
- 이벤트·SSE: 상태 변경과 이벤트/seq를 원자 저장하고 채널별 cursor로 재생한다. 접근 검증을 통과한 연결만 허용하고 heartbeat는 15초·연결 직후 한 번 전송한다.
- 경계: 로그인·인가 정책, 프로젝트 관리·사용자 REST 조회는 은현 소유다. 실행 서비스용 접근/입력 포트를 제공하며 미연결이면 fail-closed다. Claude·Terraform 실행은 추가하지 않는다.
- DB: 기존 ERD와 매핑을 사용한다. 다른 담당자의 DDL을 덮거나 임의 적용하지 않는다. 통합 검증용 독립 DB/스키마와 운영 Flyway 버전 조율은 구분한다.
- 검증·커밋: 테스트 코드는 기능과 함께 작성한다. 사용자 요청대로 전체 포맷·빌드·느린 DB 검증은 기능 구현을 모은 뒤 실행하며, 중간 기능 커밋은 아직 빌드 검증 전임을 기록한다. 실제 Jenkins·클라우드 변경 검증은 포함하지 않는다.

### 실행 기능 검증 결과

2026-10-01: 위 승환 소유 실행 기능을 구현하고 `spotlessApply check build --no-daemon --offline`을 통과했다. **91개 테스트, skipped/failure/error 0**, 이 중 실제 PostgreSQL 통합 테스트 12개다. 실제 Boot jar 기동·health UP·OpenAPI 응답과 콜백 기본 비활성/인증 미연결 거절도 확인했다.

검증 근거와 담당자 연결 항목은 [작업 일지](docs/sh/2026-10-01-execution.md)에 정리한다. 운영 Flyway 번호, 은현의 인증·입력/관리·REST 연결, 인프라의 실제 Job 프로토콜은 별도 협의·통합 범위다. 이 결과를 실제 배포나 프론트·앱 전체 동작 완료로 해석하지 않는다. 아래의 과거 단계별 “아직 구현하지 않음”은 당시 작업 기록이며 현재 실행 기능 상태는 이 절을 기준으로 한다.

## 기본 개발 환경

- 담당: 김승환
- 목적: 두 서버 담당자가 같은 빌드·DB·포맷 설정으로 기능 개발을 시작할 수 있게 합니다.
- 상태: 로컬 구현·검증 완료. 팀 공유는 이 명세를 포함한 PR의 머지 후입니다.
- 이 항목은 이미 구현한 기본 환경의 범위를 정리한 기록입니다. 이후 기능은 구현 전에 명세를 추가합니다.

### 범위와 동작

| 항목 | 명세 |
|---|---|
| 프로젝트 | Java 21, Spring Boot 3.5.16, Gradle 8.14 Kotlin DSL, 단일 모듈 |
| 패키지 루트 | `com.teamdaisy.server`, 경로는 `src/main/java/com/teamdaisy/server/` |
| 빌드 실행 | Gradle Wrapper를 사용하며 배포본 SHA-256을 검증합니다. |
| HTTP | Spring MVC 기반으로 시작합니다. Actuator의 `/actuator/health`로 상태를 확인합니다. |
| DB | PostgreSQL, JPA, Flyway를 사용합니다. `ddl-auto=validate`, `open-in-view=false`로 둡니다. |
| 로컬 DB | Docker Compose의 `postgres` 서비스로 PostgreSQL 17을 실행하거나 기존 로컬 PostgreSQL에 연결합니다. |
| 설정 | `DAISY_DB_URL`, `DAISY_DB_USER`, `DAISY_DB_PASSWORD`로 연결 설정을 주입합니다. 비밀번호 기본값은 두지 않습니다. |
| JSON | Jackson 전역 `SNAKE_CASE` 설정을 사용합니다. |
| API 문서 | springdoc-openapi 2.9.1을 사용합니다. `/v3/api-docs`, `/swagger-ui.html`을 제공합니다. 업무 API 경로와 Bearer 인증 요구가 노출됩니다. 경로 목록은 `/v3/api-docs` 를 기준으로 봅니다. |
| 포맷 | Spotless 8.10.3 + google-java-format 1.36.0. `spotlessApply`로 적용하고 `check`·`build`에서 검사합니다. |

### 후속 기능 개발

업무 패키지, DB 마이그레이션, 배포 상태·승인·SSE, Jenkins 연동·결과 수집은 아래 방향과 [전체 업무 범위](docs/work.md)를 기준으로 별도 기능 명세·구현을 준비합니다. 기존 Terraform CLI 직접 실행 계획은 현재 초안에서 제외하며, 실행 서비스와 인프라 요청·결과 계약을 구현 전에 맞춥니다.

### 검증 결과 (2026-09-29)

- Gradle Wrapper로 `spotlessApply check build --no-daemon` 성공.
- 로컬 PostgreSQL 17 연결, Flyway 초기화와 Spring Boot 기동 확인.
- `/actuator/health`에서 `{"status":"UP"}`, `/v3/api-docs`에서 OpenAPI 응답 확인.
- 테스트 소스와 업무 마이그레이션은 아직 없습니다. 테스트 태스크 결과는 `NO-SOURCE`입니다.
- Docker Compose 구성은 작성했으며, 현재 개발 머신에 Compose 실행 환경이 없어 실제 실행 검증은 하지 못했습니다. 기존 로컬 PostgreSQL 연결 경로는 검증했습니다.

## Jenkins 연동 백엔드 개발 방향 (10/1 피드백 반영)

인프라팀이 사용자 저장소의 CI/CD와 AI·Terraform 처리를 담당하고, 백엔드는 요청·승인·상태·결과를 관리합니다. 이 PR은 엔티티·공통 기반 범위이며 실행 서비스·Jenkins 어댑터는 별도 작업입니다.

### 범위와 담당

| 영역 | 구현할 동작 | 담당 |
|---|---|---|
| 배포 실행 | 배포·대상 생성, 상태 전이, 멱등성, 실행 충돌·트랜잭션 | 김승환 |
| Jenkins 연동 | 실행·중단 요청, 큐·실행 식별자 연결, 결과 수신, 장애 후 추적 | 김승환 |
| 승인·제어 | 승인된 plan 연결, stale 재승인, 취소·재시도·롤백 정책 | 김승환 |
| 실행 기반·수집 | 예외·SSE 기반, 로그·산출물·사용량 원본 수신, 인가 서비스 연결 | 김승환 |
| 인증·인가 | 로그인·Bearer 토큰, 계정·역할, 프로젝트 접근 정책·보안 설정 | 하은현 |
| 관리·조회 | 프로젝트·레포·대상 관리, 빌드·배포·plan·코드·사용량 조회 | 하은현 |
| 사용자 API | 공통 인증·SSE 적용, 실행 서비스 호출, DTO·OpenAPI·테스트 | 하은현 |

전체 기능과 선택 범위는 [work.md](docs/work.md), 상세 분담은 [승환 역할](docs/sh/roles.md)과 [은현 역할](docs/eh/roles.md)에 둡니다. 은현의 기존 코드·DDL은 보존하고 별도 PR로 대조합니다.

### 흐름과 불변 조건

1. 사용자 요청에서 배포할 커밋·대상·입력을 고정하고 배포 기록을 만듭니다.
2. Jenkins에 실행을 요청하고 서비스 배포 ID와 큐·Job·실행 번호를 연결합니다.
3. 환경별 단계·plan·로그·산출물·사용량을 수신합니다. 중복·지연 이벤트를 구분합니다.
4. 사용자가 확인한 대상별 plan에 승인을 연결하고, 승인된 동일 plan의 실행을 요청합니다.
5. 실제 완료 결과를 확인해 환경별·전체 상태와 이력을 제공합니다. 통신 시간 초과를 취소·실패 완료로 간주하지 않습니다.

- 배포 상태와 승인 유효성은 김승환의 실행 서비스 한 곳에서 관리합니다. API는 공통 인가 규칙과 입력 검증을 적용하고 해당 서비스를 호출합니다.
- 한 Jenkins 실행이 여러 대상을 처리할 수 있으므로 배포·대상·Jenkins 실행의 관계를 구분합니다.
- `attempt`는 최초 생성 포함 생성·수정 회차입니다. Jenkins 실행 횟수·단계 실행 횟수·실제 AI 호출 수와 구분하고 인프라와 의미를 맞춥니다.
- 재plan된 결과에는 이전 승인을 적용하지 않습니다. plan 참조·버전 또는 digest의 전달 방식은 연동 계약으로 정합니다.
- 사용량은 실제 호출 기록을 받아 중복 없이 집계합니다. 미확인은 NULL이며, USD 합산 후 고정 환율로 원화 환산·반올림하는 순서를 유지합니다.
- 외부 호출과 DB 트랜잭션을 분리하고, 요청 응답이 유실되면 기존 실행 확인 없이 자동으로 재실행하지 않습니다.
- DDD는 단일 모듈의 기능별 책임과 서비스 경계를 분리하는 기준으로 사용합니다. 구현을 위해 필요하지 않은 추상화·메시지 브로커는 추가하지 않습니다.

### DB 설계 및 후속 구현

- 앞선 작업은 **DB 설계만**으로 마쳤으며, 당시 작성 중이던 Java 기능 코드·보안 의존성 변경은 사용자 요청에 따라 제거했습니다. 이후 승인받은 엔티티 작업은 아래 별도 범위로 진행합니다.
- [DB 설계안](docs/database-design.md)에 ERD·테이블 사전·관계·제약·인덱스·DDD 소유 경계를 정리합니다. PR·이슈·대화의 요구를 반영하되, 추가 설계 선택은 백엔드 제안으로 구분합니다. 기존 Terraform 로컬 경로 중심 모델을 그대로 적용하지 않습니다.
- 결과 수신은 Jenkins 상태·로그·산출물 폴링입니다. 5초는 초기 제안으로 부하·지연을 확인한 뒤 조정합니다. `daisy-cd-plan`과 `daisy-cd-apply`를 분리하며 Jenkins 승인 대기를 사용하지 않습니다. request_id 검색·중복 방지, 구조화된 대상 결과·plan 원본 참조는 연동 확인이 남았습니다([DB 설계 §8](docs/database-design.md#8-jenkins-계약과-장애-처리)).
- 한 대상의 요청 → plan → 승인 → 실행 → 완료를 먼저 연결하고 중복 요청·오래된 승인·지연 이벤트·부분 실패·재시작을 검증합니다.
- 테이블·컬럼·관계는 검토 가능한 초안을 먼저 제시하고 은현의 PR 코멘트로 보완합니다. DB 설계에 인증 관련 테이블을 포함하지만 인증·인가 구현은 은현 담당입니다.
- DB 설계 단계에서는 파일 생성을 후속 범위로 남겼습니다. 이후 승인된 엔티티 범위는 아래를 따르며, Flyway 마이그레이션 작성·DB 적용은 여전히 제외합니다.

## ERD 기반 domain 엔티티 (9/30 후속 승인)

- 범위: DB 설계안의 기본 17개 테이블을 기능별 `domain` 패키지의 JPA 엔티티로 매핑합니다. 필드·키·NULL·타입, 일반 UNIQUE, 두 복합 기본키와 배포/대상 상태 타입까지만 구현합니다.
- 패키지: `identity`, `project`, `deployment`, `jenkins`, `script`, `ai`, `history`, `idempotency`. 모든 테이블을 독립 aggregate root로 취급하지 않습니다. 관계는 ID로 참조하고 양방향 연관관계·cascade를 추가하지 않습니다.
- 계정·프로젝트 등 은현 소유 데이터도 ERD 대조용 초안으로 포함합니다. 인증·인가 정책이나 동작은 구현하지 않고 은현 검토를 받습니다.
- JSONB는 기존 Hibernate/Jackson 매핑, 시각은 `Instant`, 금액은 `BigDecimal`을 사용합니다. 배포·대상 상태는 DB 계약의 소문자 문자열로 저장합니다. 미확정 역할·원천 값은 임의 enum으로 확정하지 않습니다.
- 이번 단계는 영속성 구조 초안입니다. 생성·상태 전이 등 도메인 동작, Repository·서비스·API, Jenkins 호출, Flyway·실제 DB 적용은 제외합니다. 범용 setter, 기반 엔티티, 불필요한 빈 계층도 만들지 않습니다.
- 복합 FK·부분 UNIQUE·CHECK·DB 기본값과 실행 불변 조건은 설계안에 남겨 후속 Flyway/서비스에서 구현합니다. ID 매핑이나 JPA 메타데이터 검증이 DB 무결성 구현을 대신하지 않습니다.
- 검증: DB 연결 없는 Hibernate 메타데이터 검사로 17개 테이블의 컬럼·키·타입을 ERD와 대조하고, 복합키 동등성·상태 변환을 검사한 뒤 `spotlessApply check build`를 실행합니다.
- **기동 제한:** `ddl-auto=validate`를 유지하므로 마이그레이션 없는 빈 DB에서는 엔티티 추가 후 서버가 기동하지 않습니다. 이 단계는 검토용 브랜치이며, 실제 기동·main 머지 전 호환 Flyway 마이그레이션과 PostgreSQL 검증이 필요합니다.

### 엔티티 검증 결과

- 17개 엔티티·252개 컬럼, 복합키 2개, 배포/대상 상태 타입 2개 작성.
- 별도 6.1 Sol 리뷰로 사전의 컬럼·타입·NULL·키 매핑을 대조했고 수정이 필요한 불일치를 발견하지 않았습니다.
- `spotlessApply check build --no-daemon` 성공. DB 없는 Hibernate 메타데이터·복합키·상태 변환 테스트 3개 통과.
- 마이그레이션·PostgreSQL 저장/조회·DB 제약·실제 낙관적 잠금 경쟁·서버 기동은 이번에 검증하지 않았습니다.

## common 오류 처리와 요청 추적

- 사용자 최종 승인에 따라 `common/error`의 `ErrorCode`·`DaisyException`, `common/web`의 오류 응답 DTO·전역 예외 처리기·요청 ID 필터를 구현합니다. 오류 코드만 정의하는 중간 범위에서 공통 기반 세 항목까지 확대했습니다.
- 포함: `VALIDATION_FAILED`, `UNAUTHENTICATED`, `FORBIDDEN`, `NOT_FOUND`, `TARGET_LOCKED`, `STATE_CONFLICT`, `MANIFEST_INVALID`, `RATE_LIMITED`, `INTERNAL`.
- 코드 이름은 사용자가 제공한 프론트·백엔드 계약 문서 §2를 유지합니다. enum 선언 자체가 HTTP 응답 구현이나 OpenAPI 제공 완료를 뜻하지 않습니다.
- 오류 응답은 `{ "error": { "code", "message", "details", "retryable" } }` 구조입니다. `details`가 없으면 빈 객체를 쓰고 성공 응답은 감싸지 않습니다. 인증·인가·Security 필터 구현은 은현 담당 그대로입니다.
- `DaisyException(ErrorCode, Map<String, ?>)`로 업무 경계가 허용한 필드별 안내·배포 ID 등 안전한 details를 전달합니다. 원본 입력·예외·SQL·자격증명을 map에 넣지 않으며 공통 처리기는 details를 로그에 기록하지 않습니다. map의 최상위는 방어 복사하고 중첩 값은 호출자가 안전한 불변 값으로 구성합니다.
- Spring의 낙관적 잠금 충돌은 `STATE_CONFLICT` 409로 반환합니다. `DataIntegrityViolationException` 전체를 `TARGET_LOCKED`로 바꾸지 않습니다. 실제 constraint와 요청을 아는 업무 서비스가 락 충돌·멱등 응답 재조회·그 밖의 무결성 오류를 구분해야 하며, 미분류 오류는 안전한 `INTERNAL` 응답으로 유지합니다.
- 403은 `FORBIDDEN`(권한 부족), 422는 `MANIFEST_INVALID`(`deploy.yaml` 검증 실패)로 사용자 위임에 따라 정합니다. 기존 7개와 달리 이번 백엔드 선택이며 웹·앱 공유가 필요합니다. 일반 HTTP 요청 형식 오류(400)와 manifest 내용 검증 실패(422)를 구분합니다.
- 과거 `IR_SCHEMA_INVALID`, BaseEntity·공통 성공 응답·범용 유틸은 추가하지 않습니다.
- 업무 예외는 오류 코드의 안전한 기본 메시지를 사용합니다. 원본 예외 메시지·SQL·요청 본문·rejected value·자격증명을 응답이나 공통 오류 로그로 내보내지 않습니다. 검증 실패는 필요한 필드명과 고정 안내만 제공합니다.
- 입력 검증·JSON 파싱·파라미터 오류는 400, 없는 경로는 404로 처리합니다. Spring MVC의 405·415 등도 500으로 바꾸지 않고 원래 HTTP 상태와 필요한 표준 헤더를 유지합니다. 이미 전송 중인 SSE/응답에는 JSON 오류 본문을 덧붙이지 않습니다.
- `retryable` 기본값은 보수적으로 false, `RATE_LIMITED`만 true로 제안합니다. true가 승인/apply의 무조건 자동 재실행을 허용하는 뜻은 아닙니다. 세부 소비자 계약은 공유가 필요합니다.
- `X-Request-ID`는 헤더 1개, ASCII 영문·숫자·점·밑줄·하이픈 1~64자만 수용하고, 누락·중복·잘못된 값이면 UUID를 생성하는 내부 정책입니다. 응답 헤더·요청 attribute·로그 MDC의 `request_id`를 연결합니다. 클라이언트 제공값은 추적용이지 인증·멱등성 키가 아닙니다.
- 필터 종료 시 MDC의 이전 값을 복원/제거해 요청 간 오염을 막습니다. async 재디스패치에서는 같은 요청 ID를 사용하되 임의 executor나 향후 SSE 생산 스레드로의 자동 전파까지 보장하지 않습니다. JSON 콘솔 로그는 Spring Boot 기본 기능을 사용합니다.
- Spring Security/Servlet 필터 단계 오류는 MVC advice가 처리하지 못하므로 후속 인증 진입점·접근 거부 처리기와 연결해야 합니다. CORS·SSE 구현이나 외부 프록시 설정을 완료한 것으로 보지 않습니다.
- 검증은 DB 없는 공통 MockMvc/필터 테스트와 기존 엔티티 테스트·전체 빌드로 수행합니다. 새 라이브러리·업무 API·마이그레이션은 추가하지 않습니다.

### 공통 기반 검증 결과 2026-10-01

- `spotlessApply check build --no-daemon --offline` 성공. 공통 웹 테스트 5개·필터 테스트 3개·기존 매핑 테스트 3개, 총 11개 통과.
- 9개 오류 코드, 성공 응답 비포장, 검증 필드의 snake_case·안전한 메시지, 404/405/406/415 상태·표준 헤더, 비JSON Accept에서도 오류 JSON 반환을 확인했습니다.
- SSE 헤더만 설정한 미전송 상태의 오류 응답과 이미 전송된 응답의 비변경을 구분했습니다. 요청 ID의 길이·문자·중복 검사, MDC 복원, async/error 재디스패치, 네이티브 JSON 로그의 MDC 및 공통 오류 비밀값 비노출을 검증했습니다.
- 검증 필드명은 팀 전역 snake_case 기준의 루트 필드입니다. 개별 `@JsonProperty` 별칭과 상세 배열/map 경로는 현재 계약에 포함하지 않습니다.
- 검증은 공통 처리기 로그에 한정하며 프레임워크·웹서버·프록시 전체 로그의 비밀값 차단을 보장하지 않습니다. 실제 Servlet 컨테이너의 필터 등록·SSE 스트리밍·인증 필터 통합과 DB 기동은 후속 검증입니다.

### PR #19 피드백 후속 검증 범위

- 실제 `application.yml`을 읽는 Jackson 테스트 슬라이스로 snake_case·UTC `Instant`, 안전한 details, 낙관적 잠금 409와 미분류 무결성 오류 500을 확인합니다. DB 경쟁·인가 필터의 403 검증을 대신하지 않습니다.
- JPA 엔티티는 매핑 초안이므로 DB 기본값이 NULL INSERT를 채운다고 가정하지 않습니다. 실제 생성 기능에서 필수값·생성 시각·초기 상태를 제공하며 이번 PR에 생성 동작이나 타임스탬프 정책을 추가하지 않습니다.
- 은현의 `V1__init.sql`은 #32로 현재 브랜치에 머지됐습니다. 17개 테이블의 SQL은 은현 변경 이력을 보존하며, [DB 설계 §12](docs/database-design.md#12-pr에서-확인할-계약과-인계)의 대조 목록으로 검증합니다. 이후 DB 변경 필요 여부는 #35에서 확인하고, 적용된 V1 수정 대신 후속 마이그레이션으로 관리합니다.
- 검증 결과: Java 21·기존 Gradle 캐시에서 `spotlessApply test` 및 `check build --no-daemon --offline` 성공. 공통 웹 7개·필터 3개·매핑 3개, 총 13개 통과. 실제 DB 기동·Jenkins 실행·Security 필터 통합은 미검증입니다.

### #32 통합 후 개발 기준

- V1의 계정 역할은 인증 담당이 확정한 `owner/viewer`입니다. 인증 방식·membership 검사·보안 필터 구현은 은현 담당입니다.
- #32 답변대로 실제 호출별 `ai_usage`를 유지하고, 합계만으로 가짜 호출 행을 만들지 않습니다. 합계의 별도 수신·보관과 미확인 표시 방법은 #35 연동 항목입니다.
- apply 중 중단은 요청자·시각만 기록하고 실제 결과를 기다립니다. Jenkins stop 호출·취소 완료·락 해제로 치환하지 않습니다. plan stop은 인프라 검증 후 연결합니다.
- 내부 `prepare`와 Job `daisy-cd-plan`은 연동부에서 매핑합니다. 작업명 변경이나 신규 테이블은 필요하지 않습니다.
- 공개 API의 목록 봉투·attempt 표시·다중 승인·이미지·롤백 매핑은 아래 링크의 구체적 안을 은현과 확인한 뒤 구현합니다. 이를 인프라 답변 대기로 묶지 않습니다. 실제 산출물·식별자·state 연결만 [#35](https://github.com/Softbank-Hackathon-2026-Team-Daisy/daisy/issues/35)에서 추적합니다.
- 통합 검증(2026-10-01): `check build --offline` 및 테스트 13건 통과, PostgreSQL 17의 SQL 제약 검사 27건 통과. 통합 jar의 classpath V1으로 별도 빈 DB에 Flyway 적용·JPA validate·기동 성공, health UP 및 OpenAPI 응답 확인. 실제 Jenkins·인가 통합·동시성 검증과 구분합니다. 상세는 [작업 일지](docs/sh/2026-10-01-pr19-feedback.md#통합-검증-결과-2026-10-01-1953-kst)에 기록했습니다.

## #38 통합 보완 (10/1, 김승환)

### 배포 조회 서비스 연결 (승환 구현, 은현 API 연결 후속)

- **#42 연결 보완 (10/2):** `projectIdOf(actorId, deploymentId)`로 배포 소속 프로젝트를 조회하고 `ExecutionAccess.requireRead`를 확인한 뒤 반환합니다. 없는 배포는 404, 접근 거절은 정책의 오류를 그대로 전달합니다. 조회 권한이 변경 권한을 대신하지 않으며 이후 실행 서비스의 `requireWrite`는 유지합니다. 공개 URL은 바꾸지 않습니다.
- A-02는 새 `currentByTarget(actorId, projectId, pointers)`를 사용합니다. 모든 요청 대상에 `CurrentResult(status, deployment)`를 반환하며, 포인터 NULL은 `none`, 소속·성공·종료·이미지 구조가 확인된 포인터는 `confirmed`, 포인터 확인 실패는 `unverified`입니다. 권한 404/403/401·입력 오류·DB 장애는 대상 상태로 바꾸지 않습니다. 대상별 실패는 예외 없이 반환하므로 같은 읽기 트랜잭션 안에서도 rollback-only를 만들지 않습니다.
- 기존 `current()`는 #42의 기존 호출을 깨지 않도록 유지하지만, 그 예외를 잡아 대상별 fallback으로 쓰지 않습니다. 은현님은 새 메서드로 전환하고 재호출 fallback을 제거하면 됩니다. 실제 #42 컨트롤러 변경·통합 검증은 별도입니다.
- 검증 기준: 권한 있는 배포 소속 조회·없는 배포·철회 권한, 정상/NULL/없는/다른 소속/실패/종료 시각 없는/이미지 구조 오류 포인터가 섞인 배치, 동일 트랜잭션 커밋 성공을 확인합니다. `recordBuild`는 선택한 기존 성공 빌드 확인이며 신규 빌드 등록이 아니라는 주석도 맞춥니다.
- `DeploymentQueryService.current(actorId, projectId, pointers)`는 관리 서비스가 읽은 `(targetId, currentDeploymentTargetId)`를 받아, 해당 프로젝트·대상의 성공 배포 정보를 일괄 조회합니다. 최근 성공을 임의로 현재 배포로 선택하지 않습니다. 포인터 NULL은 확인된 현재 배포 참조 없음이며 실제 인프라 부재를 보장하지 않습니다. NULL이 아닌 포인터의 소속 불일치는 404, 성공/종료 근거 부족은 409입니다.
- `deployedTo(actorId, projectId, sourceVersionIds)`는 **정확한 빌드 ID별·대상별 마지막 성공 1건**을 반환합니다. 전체 배포가 부분 실패했어도 성공 대상은 포함하고, 실패·진행 중 대상은 제외합니다. 과거 성공 이력이지 현재 가동 여부가 아닙니다. 같은 완료 시각이면 배포 ID로 순서를 고정합니다.
- 두 메서드는 매번 `ExecutionAccess.requireRead`를 호출하고 포트가 없으면 거절합니다. 최대 100개 ID의 배치·중복/빈 ID 검증, readOnly 트랜잭션, 파라미터 바인딩을 사용합니다. 관리 Repository·Entity 직접 접근, 새로운 API·테이블·관측값 갱신은 없습니다.
- 현재 배포 이미지 목록은 성공 배포에 고정된 서비스별 이미지의 명시 필드만 제공하고 입력 snapshot·자격증명·plan 원문은 노출하지 않습니다. MSA를 임의의 대표 이미지로 줄이지 않습니다. `deployedAt`은 기록된 대상 성공 완료 시각이며 실제 트래픽 전환 시각을 측정한 값은 아닙니다.
- 공개 DTO와 API 연결은 은현 담당입니다. 현재 포인터를 실제 인프라 결과에 따라 갱신하는 경로는 별도 후속이며, 조회 서비스만으로 실제 current가 자동 채워지지 않습니다. 내부 계약 상세는 `docs/execution-service-contract.md`에 기록합니다.

### 기존 인증·조회 통합 보완

- 기존 인증·조회와 실행 서비스를 한 브랜치에서 검증합니다. `ExecutionAccess`·`ExecutionInputs` 어댑터와 공개 배포 API 연결은 은현의 후속 범위로 유지합니다.
- 빌드 확인 결과의 commit·이미지가 NULL이면 NPE 대신 `STATE_CONFLICT`로 거절합니다.
- 저장 `image_refs`는 실행 도메인과 같은 `{service: {image_ref, digest, commit_sha}}`입니다. 조회 응답은 기존 `image_digest` 이름으로 변환합니다. 테이블·공개 응답 이름은 바꾸지 않습니다.
- CORS는 인증 필터보다 먼저 처리해, 허용 origin의 인증 실패 응답에도 CORS 헤더를 제공합니다. 미허용 origin은 거절하고 쿠키 인증은 추가하지 않습니다.
- OpenAPI에 HTTP Bearer/JWT scheme과 보호 경로의 인증 요구를 명시합니다. 로그인 경로는 공개 상태로 유지합니다.

## DB 마이그레이션과 인증·인가 (10/1, 하은현)

### 범위와 동작

- `V1__init.sql` 로 ERD 17개 테이블을 만듭니다. 설계 문서의 FK·CHECK·부분 UNIQUE·인덱스를 DB 제약으로 구현합니다. 엔티티의 JPA 매핑이 DB 무결성을 대신하지 않습니다.
- 복합 FK 로 프로젝트 소속을 DB 가 확인합니다. 다른 프로젝트의 `source_version`·`target`·lineage 배포를 섞을 수 없습니다.
- 순환 FK 네 쌍은 테이블 생성 뒤 `ALTER` 로 연결합니다. 삭제 CASCADE 를 두지 않고 보관은 `archived_at`·`disabled_at` 으로 합니다.
- `POST /auth/token` 으로 토큰을 발급하고 `GET /auth/me` 로 주체를 확인합니다. REST·SSE 모두 `Authorization: Bearer` 를 쓰고 쿠키는 받지 않습니다.
- 별도 토큰 테이블을 두지 않습니다. 역할·활성 여부는 토큰이 아니라 요청마다 DB 에서 다시 읽습니다. 로그아웃·개별 토큰 폐기 경로는 없습니다.
- 아이디가 없는 경우와 비밀번호가 틀린 경우를 같은 401 로 응답합니다.
- 필터 단계 오류를 `HandlerExceptionResolver` 로 넘겨 공통 오류 봉투로 응답합니다. 공통 기반 문서의 "인증 필터 오류는 MVC advice 밖" 항목을 이 방식으로 연결합니다.
- `ProjectAccessService` 가 접근·변경 권한을 판정합니다. 접근 여부는 활성 membership, 변경·승인 여부는 계정 역할로 나눕니다. 실행 서비스도 이 서비스를 호출하며 API 검사를 이유로 생략하지 않습니다.
- 없는 프로젝트와 권한 없는 프로젝트를 모두 404 로 응답합니다. 403 은 접근은 되는데 역할이 모자란 경우에만 사용합니다.
- 데모 계정은 환경변수가 있을 때만 심고 BCrypt 해시만 저장합니다. 비밀번호를 코드·마이그레이션·로그에 두지 않습니다. `DAISY_AUTH_SECRET` 이 없으면 기동하지 않습니다.
- CORS 허용 origin 은 환경변수로 받고 와일드카드를 쓰지 않습니다. `Authorization`·`Last-Event-ID`·`Idempotency-Key`·`X-Request-ID` 를 허용하고 `X-Request-ID` 를 노출합니다.

### 후속 범위

- ~~조회·관리 API 는 아직 없습니다. 인가 판정이 실제 요청 경로에 붙은 적이 없고 단위 테스트로만 확인했습니다.~~ → 10/2: 조회·관리·배포 API 가 붙었고, 인가는 아래 각 절 검증 표에서 실제 요청(401·404·403)으로 확인했습니다.
- SSE 경로의 인증 실패 전달, 실제 터널·프록시 뒤의 CORS·스트리밍은 도메인과 개발 서버가 생긴 뒤 확인합니다.
- 만료된 `pending` 승인을 `expired` 로 내리는 일은 서비스 책임입니다. 시간 조건은 PostgreSQL 인덱스 조건에 넣을 수 없습니다.
- FK 인덱스가 없는 컬럼 36곳은 예선 데이터 규모를 보고 넣지 않았습니다.

### 검증 결과 (2026-10-01)

- 빈 PostgreSQL 17 에 올려 Flyway 적용(0.39초)·`ddl-auto=validate` 통과·기동(21.9초)을 확인했습니다. 엔티티와 컬럼이 어긋나면 기동이 실패합니다.
- 제약 검사 17가지를 돌려 교차 프로젝트 참조, lineage 조합, plan·승인 중복, state 락, `seq`, 멱등 키가 의도대로 막히는 것을 확인했습니다. `bash server/docs/eh/sql/verify.sh` 로 재현합니다.
- `spotlessApply build test --no-daemon` 성공. 테스트 18개(기존 11개 + 접근 권한 7개) 통과.
- 실제 기동 후 10가지를 확인했습니다. 미인증 401, 틀린 비밀번호와 없는 계정의 동일 응답, 정상 로그인, Bearer 조회, `viewer` 역할, 변조 토큰 401, `Basic` 헤더 401, CORS preflight, OpenAPI 노출입니다.
- DB 제약과 인증 경로만 확인했습니다. 실제 배포 흐름·동시성·Jenkins 연동·SSE 재생은 이번 검증 범위가 아닙니다.

## 프로젝트 조회 API (10/1, 하은현)

### 범위와 동작

- `GET /projects` 는 로그인한 계정이 접근할 수 있는 프로젝트 목록을 돌려줍니다. 활성 membership 이 있고 보관되지 않은 것만 포함합니다.
- `GET /projects/{id}` 는 프로젝트 상세를 돌려줍니다. `ProjectAccessService.requireRead` 를 적용해 없는 프로젝트와 권한 없는 프로젝트를 모두 404 로 응답합니다.
- 목록 응답은 계약의 `{ items, next_cursor }` 봉투를 씁니다. 이번 범위에서는 전체를 한 번에 돌려주고 `next_cursor` 는 항상 null 입니다.
- 응답 필드는 `id`, `name`, `repository`, `default_branch`, `created_at` 이고 상세에는 `repository_url`, `manifest_path` 가 더해집니다. DB 컬럼명을 그대로 노출하지 않습니다.
- 데모 프로젝트는 환경변수가 있을 때만 심습니다. 계정 시딩과 같은 방식이고 데모 계정에 membership 을 함께 부여합니다.

### 후속 범위

- 커서 페이지네이션은 넣지 않았습니다. 목록이 커지면 `created_at`·`id` 기준 커서를 추가합니다.
- `POST /projects` 는 넣지 않았습니다. 저장소 연결 절차·권한이 계약에서 미결입니다.
- 승준님 `A-12` 가 요청한 `build`, `registry`, `webhook_last_at` 은 빌드 수신이 생긴 뒤에 붙입니다.
- 보관된 프로젝트의 조회 정책은 정하지 않았습니다. 지금은 목록에서만 제외합니다.

### 검증 결과 (2026-10-01)

- 빈 PostgreSQL 17 에 띄워 6가지를 확인했습니다. owner 목록의 봉투 모양, viewer 의 조회 허용, 미인증 401, 상세 응답, 없는 프로젝트 404, **멤버십 철회 뒤 프로젝트가 존재해도 404 이고 다른 계정은 영향이 없는 것** 입니다.
- 시딩 순서 오류를 실제 실행에서 찾아 고쳤습니다. `ApplicationRunner` 는 `@Order` 가 없으면 가장 마지막이라, `@Order(100)` 인 프로젝트 시더가 계정 시더보다 먼저 돌아 아무것도 심지 않았습니다. 계정 시더에 `@Order(50)` 을 붙여 순서를 명시했습니다.
- 커서 페이지네이션·보관 프로젝트 조회 정책은 확인하지 않았습니다. 목록이 한 건인 상태의 검증입니다.

## 환경별 현재 상태 조회 A-02 (10/1, 하은현)

### 왜 지금인가

`ios/SPEC.md` 182행이 D2(10/1) 요구로 `A-01·A-02·A-04` 와 개발 서버 R-08 을 적고 "은현 님 약속" 으로 표시해 두었습니다. A-02 는 우선도 **M** 이고 §6-2 가 *"앱의 핵심 화면"* 으로 적은 현황(W-01) 화면이 이 경로만 씁니다. `work.md` §2 의 *"프로젝트에 연결된 온프레미스·클라우드 대상 목록과 상태 제공"* 이 제 담당이고, 실행 서비스를 기다리지 않고 만들 수 있습니다.

### 범위와 동작

- `GET /projects/{id}/targets/status` 로 프로젝트에 연결된 배포 대상의 현재 상태를 돌려줍니다.
- `ProjectAccessService.requireRead` 를 먼저 호출합니다. 없는 프로젝트와 권한 없는 프로젝트를 모두 404 로 응답합니다.
- 목록 봉투는 기존 `GET /projects` 와 같은 `{ items, next_cursor }` 입니다. 대상 수가 프로젝트당 몇 개라 이번 범위에서는 전부 돌려주고 `next_cursor` 는 항상 null 입니다. 앱이 §6-2 에서 이 봉투를 가정했습니다.
- 보관된 대상(`archived_at` 이 있는 행)은 제외합니다.
- 정렬은 `(environment_type, name)` 으로 고정합니다. 화면에서 환경 순서가 매번 바뀌지 않게 하려는 것입니다.
- **집계하지 않습니다.** 배포 전체 상태 집계는 설계 34행대로 실행 서비스(승환) 소유입니다. 이 엔드포인트는 대상별 현재 값만 읽어 돌려줍니다.
- **`target.current_deployment_target_id` 를 갱신하지 않습니다.** 그 값을 쓰는 쪽만 맡고, 쓰는 것은 실행 서비스입니다.

### 응답 필드와 출처

`ios/SPEC.md` §6-7 의 `TargetStatus` 를 기준으로 하고, 제가 지금 근거를 가진 값만 채웁니다. **없는 값을 만들어 넣지 않습니다.**

| 계약 필드 | 출처 | 이번 PR |
|---|---|---|
| `target_id` | `target.id` | 제공 |
| `type` | `target.environment_type` (`onprem`·`aws`·`gcp`) | 제공 |
| `name` | `target.name` | 제공 |
| `connection_state` | `target.connection_state` 를 WR-04 와 같은 값(`ok`·`failed`·`unknown`)으로 변환 (10/2, 아래 WR-04 「확인이 필요한 것 ①」) | **제공 (계약에 없는 추가)** — W-04 가 "연결 안 되는 환경은 고를 수 없어요" 를 하려면 필요합니다 |
| `checked_at` | `target.connection_checked_at` | 제공 (연결 확인이 돈 적 없으면 null) |
| `current.deployment_id` | `deployment_target.deployment_id` | 제공 |
| `current.commit` | `deployment.commit_sha` | 제공 |
| `current.deployed_at` | `deployment_target.finished_at` | 제공 |
| `current.image` | `deployment.image_refs` 평탄화 | ~~미제공 (null)~~ → #42 부터 제공. 서비스가 둘 이상이면 `images[]` |
| `url` | `deployment_target.result` 의 `service_url` | **미제공 (null)** — `apply-result.json` 이 아직 인프라에 없습니다 (#17) |
| `health` | 같은 곳 | **항상 `unknown`** — 헬스 결과가 지금 apply 로그에만 있습니다 (#17) |
| `health_summary` | 같은 곳 | **미제공 (null)** |
| `image_digest` | `source_version.image_refs` | **미제공 (null)** — WR-09 동일성 검증은 빌드 수신 뒤입니다 |

`current` 는 그 대상에 한 번도 배포가 끝난 적이 없으면 통째로 null 입니다. **이번 PR 시점에는 항상 null** 이고, 이유가 둘입니다.

1. 실행 서비스가 아직 없어 `deployment_target` 에 행이 생기지 않습니다.
2. **소유 경계입니다.** 설계 2장이 `deployment` 모듈(Deployment·DeploymentTarget)을 승환 소유로, `project` 모듈(Project·Target·SourceVersion)을 은현 소유로 나눴습니다. `work.md` §14 가 *"다른 담당 영역의 Repository·Entity를 직접 사용하지 않고 서비스 계약으로 연결합니다"* 로 두었으므로, `current` 를 채우려면 **deployment 모듈의 조회 서비스 계약이 필요합니다.** `target.current_deployment_target_id` 까지는 제 소유라 읽고, 그 ID 가 가리키는 행은 읽지 않습니다.

모양만 먼저 고정해 앱이 목업을 떼고 붙을 수 있게 하는 것이 이번 범위입니다.

> 10/2: #42 부터 `current` 를 승환님 `currentByTarget` 로 읽습니다. 다만 `target.current_deployment_target_id` 를 갱신하는 코드가 아직 없어서(실행 결과 수신 #35 와 함께 붙음), **배포가 성공해도 그 전까지 `current` 는 null 입니다.** 화면에서 "아직 배포 없음" 으로 보이는 이유가 이것입니다.

### 데모 대상 시딩

현황 화면이 빈 목록이면 앱이 붙었는지 알 수 없어서, 데모 프로젝트에 대상 세 개(`onprem`·`aws`·`gcp`)를 심습니다.

- 환경변수가 있을 때만 심습니다. 기존 계정·프로젝트 시더와 같은 방식입니다.
- **`connection_state` 는 `unknown` 으로 심습니다.** 실제 연결 확인을 한 적이 없는데 `connected` 로 심으면 확인하지 않은 상태를 확인한 것처럼 보여 주게 됩니다.
- `state_identity` 는 `{project_id}/{target_id}` 형태로 둡니다. 정규화 규칙은 인프라와 맞춘 뒤 서버가 검증·저장하기로 해서(#32 리뷰), 그 전까지 쓰는 임시 값입니다.
- 저장소 연결 절차가 생기면 걷어냅니다.

### 후속 범위

- `url`·`health`·`health_summary`·`image_digest`·`current.image` 는 인프라 산출물이 생긴 뒤 채웁니다. 어느 것도 기본값으로 채우지 않습니다.
- 커서 페이지네이션은 넣지 않습니다. 대상이 많아지면 `(environment_type, name)` 기준 커서를 붙입니다.
- A-10 `POST /targets/{id}/test`(연결 테스트)와 A-11 `GET /targets/{id}/resources`(리소스 보기)는 이번 범위가 아닙니다. 둘 다 실제 대상·Terraform state 에 붙어야 해서 인프라 쪽 경로가 필요합니다 (이슈 #13).
- 대상 생성·수정·삭제는 넣지 않습니다. `work.md` §2 가 삭제 지원 범위를 별도 합의 사항으로 두었습니다.
- SSE 로 같은 정보를 밀어 주는 것은 승환님 기반 위에 붙입니다. 앱은 D2 에 5초 폴링으로 씁니다.

### 검증 결과 (2026-10-01)

검사 항목을 먼저 적고 그대로 돌렸습니다. 빈 PostgreSQL 17 에 띄워 실제 요청으로 확인했습니다.

| | 검사 | 결과 |
|---|---|---|
| V1 | 토큰 없이 호출 | 401 |
| V2 | 없는 프로젝트 | 404 |
| V3 | 멤버가 아닌 프로젝트 | **404**. 403 이 아닙니다 |
| V4 | `viewer` 계정 조회 | 200 |
| V5 | 응답 봉투 | `{ items, next_cursor }`, `next_cursor` 는 null, 필드가 snake_case |
| V6 | 대상이 없는 프로젝트 | `{"items":[],"next_cursor":null}` — 오류가 아닙니다 |
| V7 | 배포 이력이 없는 대상 | `current` 는 null, `health` 는 `"unknown"`, `url`·`health_summary`·`image_digest`·`checked_at` 은 null |
| V8 | 보관된 대상 | `archived_at` 을 넣은 대상이 목록에서 빠졌습니다 |
| V9 | 정렬 | `aws → gcp → onprem` 으로 고정 |
| V10 | **다른 프로젝트의 대상** | 다른 프로젝트에 대상을 넣고 확인했습니다. 섞이지 않습니다 |
| V11 | OpenAPI | `/projects/{projectId}/targets/status` 와 `PageResponseTargetStatusResponse`·`TargetStatusResponse`·중첩 `Current` 스키마가 노출됩니다 |

- 단위 테스트 4개를 더했습니다. **접근 판정이 막으면 대상 질의가 아예 돌지 않는 것**(응답 시간으로 존재가 새지 않게), 대상 0개가 빈 목록인 것, 근거 없는 필드가 null 인 것, `viewer` 조회입니다.
- `./gradlew --no-daemon spotlessApply spotlessCheck check build` 성공.
- 데모 대상 3개가 `connection_state='unknown'` 으로 심기는 것을 DB 에서 확인했습니다.

V10 이 핵심이었습니다. 나머지가 다 맞아도 여기서 새면 다른 팀의 환경 이름이 보입니다.

**확인하지 않은 것** — `current` 가 채워진 응답은 확인하지 못했습니다. 실행 서비스와 조회 계약이 없어 채울 경로가 없습니다. 커서 페이지네이션, 대상이 많을 때의 성능, SSE 로 같은 정보를 밀어 주는 경로도 이번 범위가 아닙니다.

## 빌드 목록 조회 A-06 (10/1, 하은현)

### 범위와 동작

- `GET /projects/{id}/builds?cursor=&limit=` 로 프로젝트가 받은 빌드 결과를 최근 순으로 돌려줍니다. 소비자 모델은 `ios/SPEC.md` §6-7 의 `Build` 입니다.
- `ProjectAccessService.requireRead` 를 먼저 호출합니다. 없는 프로젝트와 권한 없는 프로젝트를 모두 404 로 응답합니다.
- 봉투는 `{ items, next_cursor }` 입니다. **A-02 와 달리 실제 커서를 넣었습니다.** 빌드는 커밋마다 쌓여서 목록이 자라고, 설계 5.5 가 이미 `INDEX(project_id, received_at DESC, id)` 를 그 용도로 두었습니다.
- 정렬은 `received_at DESC, id DESC` 입니다. `received_at` 이 같은 행이 있을 수 있어 `id` 를 동반 키로 씁니다.
- `limit` 기본값 20, 최대 100 입니다. 범위를 넘으면 400 이 아니라 최대값으로 깎습니다 — 목록 조회가 한도 때문에 실패하지 않는 쪽이 낫습니다.
- `cursor` 는 **불투명한 문자열**입니다. 소비자가 파싱하지 않도록 base64url 로 감쌉니다. 해독할 수 없거나 형식이 깨진 커서는 400 입니다.
- 마지막 페이지의 `next_cursor` 는 null 입니다.
- `source_version_id` 를 내보냅니다. 승환 S1 의 *"빌드 목록에 `source_version_id` 를 내보내고 `POST /projects/{id}/deployments` 는 그 ID 와 `target_ids` 로 선택하게 한다"* 를 따릅니다.

### 응답 필드와 출처

| 계약 필드 | 출처 | 이번 PR |
|---|---|---|
| `source_version_id` | `source_version.id` | 제공 (S1 요청) |
| `commit` | `source_version.commit_sha` | 제공 |
| `branch` | `source_version.branch` | 제공 (없으면 null) |
| `pipeline.status` | `source_version.status` 를 변환 | 제공 — 아래 상태 대조 참고 |
| `pipeline.run_url` | `source_version.run_url` | 제공 (없으면 null) |
| `image` | `source_version.image_refs` 평탄화 | 서비스가 하나면 제공, 여러 개면 null + `images[]` |
| `images[]` | 같은 곳 | 서비스가 둘 이상일 때만 |
| `started_at`·`finished_at` | 같은 이름 | 제공 (없으면 null) |
| `error_summary` | 같은 이름 | 제공 (없으면 null) |
| `received_at` | 같은 이름 | 제공 — 커서 기준이라 소비자도 순서를 알 수 있게 내보냅니다 |
| `message`·`author`·`committed_at` | 없음 | **미제공** — 승환 S1 이 *"원천 없는 커밋 설명·작성자·시각은 후순위"* 로 두었습니다. GitHub 을 따로 호출해 채우지 않습니다 |
| `deployed_to[]` | `deployment` 모듈 | ~~미제공 (null)~~ → #42 부터 승환님 조회 서비스로 제공 |

### 상태 대조 — 소비자 enum 에 `pending` 자리가 없습니다

승환 S1 이 *"나머지 상태도 기존 소비자 enum 을 대조하고, DB enum 을 API 에 그대로 노출하지 않는다"* 로 두어서 대조했습니다.

| DB (`ck_sv_status`) | 소비자 계약 (`ios/SPEC.md` §6-7) |
|---|---|
| `succeeded` | `success` |
| `running` | `running` |
| `failed` | `failed` |
| **`pending`** | **대응 값 없음** |

`pending` 은 "빌드 결과를 받았지만 아직 시작 전" 입니다. **`running` 으로 보내지 않습니다** — 시작하지 않은 것을 진행 중으로 표시하는 건 없는 사실을 만드는 일입니다. 목록에서 빼는 것도 아닙니다. 사용자는 빌드가 접수된 것을 봐야 합니다.

**그래서 `queued` 를 네 번째 값으로 내보냅니다.** 소비자 계약에 없는 값이라 웹·앱에 알렸습니다. **웹은 받기로 했습니다** (W-03 에 "대기 중", [#38 코멘트](https://github.com/Softbank-Hackathon-2026-Team-Daisy/unibloom/pull/38#issuecomment-5931767944)). 앱은 아직 답이 없습니다. 앱이 받기 어렵다면 `pending` 행을 목록에 포함한 채 `pipeline.status` 만 null 로 두는 쪽으로 바꾸겠습니다.

### `image_refs` 모양 — #36 실행 도메인과 통합

초기 조회 구현의 `image_digest` 저장 키 가정을 실행 도메인의 `digest`에 맞췄습니다. 공개 응답은 기존 `image_digest`를 유지합니다. 자세한 검증 조건은 [실행 연결 계약](docs/execution-service-contract.md)의 ExecutionInputs JSON 저장 형태를 따릅니다.

```jsonc
{ "<서비스명>": { "image_ref": "docker.io/team/app:<전체 커밋 해시>", "digest": "sha256:<64자리 hex>", "commit_sha": "<전체 커밋 해시>" } }
```

- 서비스가 **하나**면 `image` 에 그 `image_ref`, `image_digest` 에 그 digest 를 담습니다.
- 서비스가 **둘 이상**이면 `image`·`image_digest` 를 null 로 두고 `images: [{service, image_ref, image_digest}]` 를 채웁니다. 승환 S5 의 제안 그대로입니다.
- **임의의 첫 서비스를 고르거나 digest 를 합쳐 하나로 만들지 않습니다.**
- 모양이 다르거나 해독할 수 없으면 `image`·`images` 를 **null 로 두고 오류를 내지 않습니다.** 조회가 깨지는 것보다 그 필드만 비는 게 낫습니다.

실제 Jenkins 수신 데이터는 이 저장 형태로 변환·검증해야 하며, 현재 인프라가 그대로 제공한다고 가정하지 않습니다.

### 후속 범위

- `deployed_to[]` 는 `deployment` 모듈 조회 계약이 생긴 뒤 채웁니다.
- `message`·`author`·`committed_at` 은 원천이 생긴 뒤입니다. 후순위입니다.
- `#13` 의 `Build.steps[]`(W-03 GitHub Actions 단계)는 넣지 않습니다. Jenkins `daisy-ci` 가 단계별 결과를 보내기 전에는 만들 수 없고, 승환 S2 가 *"Job 단계를 대상 단계로 꾸미지 않는다"* 로 두었습니다.
- 빌드 수신 경로(`POST`)는 승환 소유입니다. 이 PR 은 조회만입니다.

### 검증 결과 (2026-10-01)

검사 항목을 먼저 적고 그대로 돌렸습니다. 빈 PostgreSQL 17 에 띄워 빌드 6건(수신 시각이 같은 두 건 포함)과 다른 프로젝트의 빌드 1건을 넣고 실제 요청으로 확인했습니다.

| | 검사 | 결과 |
|---|---|---|
| B1 | 토큰 없이 호출 | 401 |
| B2 | 없는 프로젝트 | 404 |
| B3 | 멤버가 아닌 프로젝트 | **404**. 403 이 아닙니다 |
| B4 | 빌드가 없는 프로젝트 | `{"items":[],"next_cursor":null}` |
| B5 | 정렬 | `received_at DESC, id DESC`. 수신 시각이 같은 두 건이 `id` 로 갈립니다 |
| B6 | 상태 변환 | `succeeded→success`, `pending→queued`, `running`·`failed` 그대로 |
| B7 | `limit` 경계 | `0`·`-1` 은 400, `101` 은 100 으로 깎여 200 |
| B8 | 커서 왕복 | `limit=2` 로 3페이지를 받아 **6건이 중복·누락 없이** 전체 목록과 같았습니다 |
| B9 | 마지막 페이지 | `next_cursor` 가 null |
| B10 | 깨진 커서 | 400 |
| B11 | `received_at` 이 같은 행 | 같은 시각의 두 건이 서로 다른 페이지에 걸쳐도 건너뛰지 않았습니다 |
| B12 | 단일 서비스 `image_refs` | `image`·`image_digest` 채워짐, `images` 는 null |
| B13 | 다중 서비스 `image_refs` | `image`·`image_digest` null, `images[api, web]` |
| B14 | 모양이 다른 `image_refs` | 오류 없이 `image`·`images` 모두 null |
| B15 | **다른 프로젝트의 빌드** | 섞이지 않습니다 |
| B16 | OpenAPI | 경로와 `PageResponseBuildResponse`·`BuildResponse`·`Pipeline`·`ServiceImage` 스키마 노출 |

- 단위 테스트 11개를 더했습니다. 상태 변환 4개(`pending` 이 `running` 이 되지 않는 것 포함), `image_refs` 평탄화 5개, 커서 왕복·깨진 커서 2개입니다. 전부 순수 함수라 DB 없이 돕니다.
- `./gradlew --no-daemon spotlessApply spotlessCheck check build` 성공.

**B16 에서 결함을 하나 찾아 고쳤습니다.** OpenAPI 가 `principal` 을 쿼리 파라미터로 노출하고 있었습니다. `@CurrentAccount AuthPrincipal` 은 인증 필터가 넣어 둔 주체를 argument resolver 가 채우는 값인데, springdoc 이 알려진 애너테이션이 아닌 인자를 쿼리로 보기 때문입니다. 보호 경로 **5개 전부**가 그랬습니다 (`/auth/me`, `/projects`, `/projects/{id}`, `targets/status`, `builds`). 소비자에게 `?principal=...` 을 보내라고 알려주는 문서였습니다. `SpringDocUtils.addAnnotationsToIgnore(CurrentAccount.class)` 로 숨겼습니다. 이슈 #13 의 완료 기준이 *"받은 건 OpenAPI 에 나와 있어요"* 라서, 문서가 틀리면 계약이 틀린 것과 같습니다.

**확인하지 않은 것**

- `deployed_to[]` 가 채워진 응답은 확인하지 못했습니다. `deployment` 모듈 조회 계약이 없습니다.
- 빌드가 수천 건일 때의 커서 성능은 보지 않았습니다. 설계 5.5 의 `INDEX(project_id, received_at DESC, id)` 를 쓰는 질의라는 것만 확인했습니다.
- 실행 도메인에서 수용한 `image_refs`의 digest가 조회 projection까지 보존되는 회귀 테스트를 추가했습니다. 실제 Jenkins 수신부터 조회까지의 연결은 아직 검증하지 않았습니다.

## 실행 서비스 연결 — 어댑터와 공개 배포 API (10/2, 하은현)

> **스펙 리뷰를 먼저 받습니다.** 7시 연동 일정 때문에 구현도 같이 올렸고, 아래 「확인이 필요한 것」에서 갈리면 코드를 그에 맞춰 고칩니다. 구현 범위는 「구현 상태」 절에 있습니다.
> 기준: #40 (`server/feat-backend-integration`, `82edcd0`) 의 `ExecutionAccess`·`ExecutionInputs`·`DeploymentExecutionService`·`EventSseService`·`DeploymentQueryService`, `docs/execution-service-contract.md`.
> 반영한 코멘트: #36 승환(22:39)·도영 리뷰, #13 승환(22:39), #40 승준(22:54), 승환 메시지(23:58 — 조회 계약 push, "그렇게 개발해주셔도 좋아요").

### 범위

#40 이 요청한 연결 작업 네 가지입니다.

| | 무엇 | 이 절의 깊이 |
|---|---|---|
| ① | `ExecutionAccess` 어댑터 | 구현할 수준까지 |
| ② | `ExecutionInputs` 어댑터 | 구현할 수준까지 |
| ③ | 공개 REST·SSE 연결 (생성·승인·취소·재시도·롤백·이벤트) | 경로·요청·검증까지. 응답 DTO 는 조회 API(A-04)와 함께 정합니다 |
| ④ | 승인 요청 변환 | 구현할 수준까지 |
| ⑤ | A-02 `current`·A-06 `deployed_to` 연결 (`82edcd0` 의 `DeploymentQueryService`) | 구현할 수준까지 |

이번 범위가 아닌 것: 조회 API A-03·A-04·A-05·A-07. 응답 대부분이 `deployment` 모듈이라 그쪽 조회 계약이 더 필요합니다. 단 ④ 를 위해 A-04 에 넣을 승인 ID 필드 이름은 여기서 정합니다.

### ① `ExecutionAccess` 어댑터

`project/access/ExecutionAccessAdapter` 가 `deployment.application.ExecutionAccess` 를 구현합니다. 의존 방향은 `project → deployment` 의 인터페이스 하나뿐이고, `deployment` 는 제 인증 타입을 모릅니다.

| 메서드 | 동작 |
|---|---|
| `requireRead(actorId, projectId)` | `actorId` 로 계정을 읽습니다. 없거나 비활성이면 **401 `UNAUTHENTICATED`**. 있으면 `AuthPrincipal` 을 만들어 `ProjectAccessService.requireRead` 로 위임합니다 |
| `requireWrite(actorId, projectId)` | 같은 방식으로 `ProjectAccessService.requireWrite` 로 위임합니다 |

- 판정은 기존 그대로입니다. **없는 프로젝트·비멤버·철회된 멤버십은 모두 404, 접근은 되는데 `viewer` 면 403.**
- 역할은 `actorId` 로 **DB 에서 다시 읽습니다.** 필터가 인증한 뒤 같은 요청 안에서 계정이 비활성화돼도 막힙니다.
- 호출한 쪽의 트랜잭션에 참여하고 읽기만 합니다. 잠금을 걸지 않고 외부 HTTP 도 부르지 않습니다.
- `actorId` 는 컨트롤러가 인증된 principal 에서만 꺼냅니다. 요청 본문에서 받지 않습니다.

### ② `ExecutionInputs` 어댑터

`project/execution/ExecutionInputsAdapter` 가 구현합니다. 네 메서드 모두 **호출한 쪽의 트랜잭션 안에서 읽기만** 합니다. 새 트랜잭션을 열지 않고, 추가 잠금을 걸지 않고, 외부 HTTP 를 부르지 않습니다. 잠금 순서(`project → deployment → target(ID 정렬) → state identity`)는 실행 서비스가 쥡니다.

#### `capture(actorId, projectId, sourceVersionId, targetIds, input)`

| 검사 | 실패하면 |
|---|---|
| `sourceVersionId` 가 있고 이 프로젝트의 빌드다 | 404 `NOT_FOUND` — 다른 프로젝트 빌드와 없는 빌드를 구분하지 않습니다 |
| 그 빌드가 `succeeded` 다 | 409 `STATE_CONFLICT` |
| `image_refs` 가 계약 모양이고, 모든 서비스의 `commit_sha` 가 빌드의 `commit_sha` 와 같다 | 409 `STATE_CONFLICT` |
| 각 `targetIds` 가 이 프로젝트의 보관되지 않은 대상이다 | 404 `NOT_FOUND` — 다른 프로젝트 대상과 없는 대상을 구분하지 않습니다 |
| `input` 이 허용 키만 가진다 (아래) | 400 `VALIDATION_FAILED` |

**commit 으로 다른 빌드를 고르지 않습니다.** 받은 `sourceVersionId` 하나만 봅니다.

돌려주는 값 (키는 `snake_case`):

| 필드 | 내용 | 근거 |
|---|---|---|
| `repository` | `repository_id`, `repository_url`, `default_branch`, `manifest_path`, `repository_credential_ref` | 설계 338·664행 |
| `commonInput` | `{ "hash_format_version": 1, "strategy": "recreate" }` | 설계 339행, `Deployment.java` 가 `1` 만 받음 |
| `targets[].snapshot` | `name`, `environment_type`, `config`, `config_revision`, `credential_ref`, `credential_version` | 설계 364·665행 |
| `targets[].stateIdentity` | `target.state_identity` | 설계 665행 |
| `source` | `BuildInput(id, commit_sha, image_refs)` — **DB 에 저장된 값** | 계약 「ExecutionInputs JSON 저장 형태」 |

- **자격증명은 참조만 넘깁니다.** `credential_ref`·`credential_version`·`repository_credential_ref` 를 그대로 넘기고 복호화하지 않습니다.
- `input` 은 지금 `strategy` 하나만 받습니다. 값은 `recreate` 만 허용합니다 (계약: *"현재 전략은 recreate만 지원"*). 다른 키나 `hash_format_version` 을 사용자가 보내면 400 입니다. 사용자가 해시 형식 번호를 바꾸지 못하게 하려는 것입니다.

#### `projectName(projectId)`

`project.name` 을 돌려줍니다. 없으면 404. 승인 대기 생성 때 실행 서비스가 `approval.confirmation_text` 에 고정합니다.

#### `verifyFrozen(actorId, projectId, frozen)`

재시도·롤백 때 저장된 입력이 지금도 유효한지 봅니다. 권한은 실행 서비스가 앞에서 `requireWrite` 로 이미 확인했으므로 다시 보지 않습니다.

| 검사 | 실패하면 |
|---|---|
| `frozen.projectId` 가 `projectId` 와 같다 | 409 `STATE_CONFLICT` |
| 각 대상이 아직 이 프로젝트에 있고 보관되지 않았다 | 409 `STATE_CONFLICT` |
| 각 대상의 `state_identity` 가 고정 값과 같다 | 409 `STATE_CONFLICT` — 다른 state 에 apply 하게 되는 것을 막습니다 |
| `source` 가 있으면 그 빌드가 같은 프로젝트·같은 commit·`succeeded` 다 | 409 `STATE_CONFLICT` |

`config_revision`·`credential_version` 이 바뀐 경우는 아래 「확인이 필요한 것」 ② 입니다.

#### `recordBuild(result)`

| 검사 | 실패하면 |
|---|---|
| `result.sourceVersionId` 가 있다 | 409 `STATE_CONFLICT` |
| 그 빌드가 `result.projectId` 의 것이고 `commit_sha` 가 같다 | 409 `STATE_CONFLICT` |
| 그 빌드가 `succeeded` 이고 `image_refs` 가 계약 모양이다 | 409 `STATE_CONFLICT` |

통과하면 **DB 에 저장된** `BuildInput` 을 돌려줍니다. `result` 의 값을 그대로 되돌려주지 않습니다. 실행 서비스가 둘을 비교해 다르면 거절하게 하려는 것입니다. `source_version` 에 쓰지는 않습니다 — 이 부분이 「확인이 필요한 것」 ③ 입니다.

### ③ 공개 REST·SSE

| ID | 경로 | 요청 | 실행 서비스 호출 | 성공 |
|---|---|---|---|---|
| WR-05 | `POST /projects/{id}/deployments` | `{ source_version_id, target_ids[], commit?, strategy? }` | `create` | 201 |
| W-01 | `POST /deployments/{id}/approvals` | ④ 참고 | `decide` | 202 |
| WR-08 | `POST /deployments/{id}/cancel` | `{ target_ids[] }` | `cancel` | 202 |
| W-05b·W-08 | `POST /deployments/{id}/retry` | `{ target_ids[] }` | `retry` | 201 |
| WR-14 | `POST /deployments/{id}/rollback` | `{ target_ids[], reason, trigger_deployment_id? }` — `reason` 필수·1000자 이하 (웹은 자동으로 채움) | `rollback` | 201 |
| E-01 | `GET /deployments/{id}/events` | `Last-Event-ID` 헤더, `?event_type=` | `openDeployment` | SSE |
| E-02 | `GET /projects/{id}/events` | `Last-Event-ID` 헤더, `?event_type=` | `openProject` | SSE |

- **모든 POST 는 `Idempotency-Key` 헤더가 필수**입니다 (R-05). 없으면 400.
- **`/deployments/{id}/...` 경로는 `DeploymentQueryService.projectIdOf(actorId, deploymentId)` 로 프로젝트를 찾습니다** (044a436). 없는 배포와 접근할 수 없는 배포는 404 입니다. 조회 권한만 확인하는 메서드라, 변경 권한(viewer 403)은 실행 서비스의 `requireWrite` 가 그대로 봅니다.
- 다섯 명령의 성공 응답은 생성과 같은 `{ id, project_id, state }` 입니다. 재시도·롤백의 `id` 는 새로 만든 배포입니다.
- 재시도 경로는 확정입니다. 승환(#42)·승준(#42, 10/2 02:50)·도영(Slack, 10/2 09:57)이 동의했습니다. 내부는 새 배포를 만드는 `retry` 에 연결합니다.
- `actorId` 는 `@CurrentAccount` 에서만 꺼냅니다.
- 입력 검증은 컨트롤러에서 길이·형식만 보고, 업무 규칙은 실행 서비스와 ② 에 맡깁니다. 같은 검사를 두 곳에 두지 않습니다.
- `DaisyException` 은 기존 전역 처리기로 보냅니다. 상태 코드는 실행 서비스가 정한 것(생성·재시도·롤백 201, 승인·취소 202)을 그대로 씁니다.
- **웹은 `source_version_id` 로 바꾸기로 했습니다** (#36 도영 리뷰: *"웹 W-04도 A-06 빌드의 `source_version_id`로 고르고 보내게 바꿀게요"*). 앱은 아직 확인 전이고 명세에는 `{ commit, target_ids }` 가 남아 있어, S1 대로 **전환 기간에는 둘 다 받습니다.** `source_version_id` 는 필수이고, `commit` 이 함께 오면 그 빌드의 `commit_sha` 와 같은지 봅니다 (다르면 400). `commit` 만으로 빌드를 고르지는 않습니다. `strategy` 는 생략하면 `recreate`, 다른 값은 400 입니다.
- SSE 는 `text/event-stream`·`Cache-Control: no-cache` 를 붙이고, 인증은 REST 와 같은 Bearer 헤더입니다.
- 응답 본문은 지금 실행 서비스의 최소 응답을 그대로 내보내지 않고, A-04 `Deployment` 요약 DTO 로 바꿉니다. 그 DTO 는 A-04 와 함께 정합니다. **그 전까지는 `{ id, project_id, state }` 만** 돌려줍니다. 이름은 소비자 `Deployment` 모델(`ios/SPEC.md` 326행)과 같습니다 — 웹이 응답의 `id` 로 다음 화면에 갑니다 (#42 리뷰).
- 모두 OpenAPI 에 나오게 하고, `principal` 이 쿼리 파라미터로 새지 않는지 확인합니다 (#38 에서 한 번 샜습니다).

### ④ 승인 요청 변환

```jsonc
POST /deployments/{id}/approvals
Idempotency-Key: <키>
{
  "kind": "plan",
  "decision": "approve",            // approve | reject
  "confirm_text": "sample-monolith", // 삭제가 있는 plan 이면 필수 (검증은 실행 서비스)
  "comment": "...",                  // 선택
  "items": [ { "target_id": "tgt_aws", "approval_id": "apv_7" } ]
}
```

| 규칙 | 실패하면 |
|---|---|
| `kind` 는 생략하면 `plan`, 다른 값은 거절 (웹·앱이 `plan` 만 써서 빼고 보내기도 함, #43) | 400 |
| `decision` 은 공개 값 **`approve`·`reject`** 만. 내부로는 `approved=true/false`. 저장 상태 `approved`·`rejected` 는 받지 않습니다 | 400 |
| `items` 가 비어 있지 않다 | 400 |
| **`target_id` 가 중복되지 않는다 — Map 으로 바꾸기 전에 검사합니다.** 중복을 Map 에 넣으면 앞 항목이 조용히 덮입니다 | 400 |
| 각 항목에 `target_id`·`approval_id` 가 있다 | 400 |

통과하면 `Map<target_id, Decision(approval_id, approved, confirm_text)>` 으로 바꿉니다. **모든 항목에 같은 `decision`·`confirm_text` 를 넣습니다** (계약: *"공개 요청의 단일 decision·confirm_text를 API에서 각 항목에 동일하게 전달"*). 승인 대기 대상 전체와 맞는지, 옛 승인인지는 실행 서비스가 판정합니다 (하나라도 어긋나면 전체 409).

`comment` 는 실행 서비스에 넘길 자리가 없어서 지금은 저장하지 않습니다. OpenAPI 설명에 그렇게 적습니다.

**`items` 가 비면 400 입니다.** 승인 대기 전체로 해석하지 않습니다. 사용자가 본 대상만 승인한다는 S4 의 원칙이라, 서버가 대상을 채워 넣으면 화면에 없던 대상까지 승인될 수 있습니다.

**A-04 에 `pending_approvals: [{ target_id, approval_id }]` 로 승인 ID 를 줍니다** (#40 승준 질문의 1번). S4 가 제안한 이름이고 `items` 와 모양이 같아 그대로 보낼 수 있습니다. `targets[].approval_id`·`pending_approval` 은 쓰지 않습니다. A-04 를 만들 때 넣습니다.

### ⑤ A-02 `current`·A-06 `deployed_to` 연결

`DeploymentQueryService` 를 그대로 부릅니다. 대상 목록·빌드 페이지는 제가 읽고, 포인터·ID 만 넘깁니다.

**A-02** — `findActiveByProject` 로 읽은 대상의 `(id, current_deployment_target_id)` 를 `current()` 에 넘기고, 결과를 `current` 로 바꿉니다.

| 공개 필드 | 값 |
|---|---|
| `current.deployment_id` | `deploymentId` |
| `current.commit` | `commitSha` |
| `current.deployed_at` | `deployedAt` — 대상 성공 완료 시각. 트래픽 전환 시각이 아닙니다 |
| `current.image`·`image_digest` | 서비스가 **정확히 하나**일 때만. 여럿이면 null 로 두고 `current.images[{service, image_ref, image_digest}]` 를 줍니다 (A-06 과 같은 S5 규칙) |

**A-06** — 페이지의 빌드 ID 를 `deployedTo()` 에 넘기고 `deployed_to[{ target_id, deployment_id, deployed_at }]` 로 바꿉니다. **조회했는데 성공 이력이 없으면 `[]`, 조회 자체를 못 했으면 null** 입니다. 과거 성공 이력이지 지금 그 버전이 떠 있다는 뜻이 아닙니다.

**대상 하나가 화면 전체를 깨지 않게 합니다.** 처음 `current()` 는 포인터 하나만 잘못돼도 404·409 로 전체를 거절했습니다. #42 리뷰 뒤 승환이 `currentByTarget()`(044a436)을 열어서, 포인터 확인에 실패한 대상은 예외 없이 `unverified` 로 돌려받습니다. 권한 오류(401·403·404)·입력 오류·DB 장애는 그대로 올라옵니다. 제 쪽에는 대상별 재조회나 예외 처리가 없습니다.

**`current: null` 의 뜻을 공개 계약에 적습니다.** 승환 정의대로 *"확인된 현재 참조 없음"* 이지 "배포가 없다"가 아닙니다. 지금은 포인터를 갱신하는 경로가 없어 **실제로 배포됐어도 null** 입니다. 웹은 *"`current`가 null이면 '아직 배포 없음'으로"* 보여주기로 했는데(#38 도영), 이 문구는 사실과 다를 수 있습니다. **"확인된 배포 없음" 또는 "—"** 로 바꿔 달라고 웹·앱에 알립니다. `current_status` 를 함께 두어 `none`(포인터 없음)·`confirmed`(확인됨)·`unverified`(포인터는 있으나 확인 실패)를 구분합니다.

**A-02 는 목록 조회와 같은 읽기 트랜잭션에서 부릅니다.** 처음에는 `current()` 의 예외를 잡으면 바깥 트랜잭션이 롤백 전용이 되어 `UnexpectedRollbackException`(500)이 나는 것을 실측하고 A-02 만 `NOT_SUPPORTED` 로 돌렸습니다. `currentByTarget()` 은 대상 실패로 예외를 던지지 않아서 `NOT_SUPPORTED` 를 뺐습니다. 실측 (10/2, 빈 PostgreSQL 17, 대상 3개에 성공·대기·없음 포인터, 클래스 기본 읽기 트랜잭션): **200**, `confirmed`·`unverified`·`none`, `UnexpectedRollbackException` 0건.

**포인터 갱신은 제 몫입니다 (후속).** `target.current_deployment_target_id` 는 제 영역이라 실제 결과에 따라 바꾸는 서비스를 제가 열어야 합니다. 오래된 결과나 "가장 최근 시각" 만으로 바꾸지 않는다는 승환의 원칙을 따릅니다. 어떤 결과를 근거로 바꿀지는 #35 의 실제 결과 계약이 정해진 뒤 정합니다. **그 전까지 A-02 `current` 는 항상 null 입니다.**

### #42 리뷰 반영 (10/2, 승환 리뷰 00:59)

| 질문 | 답 | 반영 |
|---|---|---|
| ① 배포 ID → 프로젝트 | 승환이 `projectIdOf(actorId, deploymentId)` 를 044a436 으로 제공. 없는·접근 못 하는 배포는 404, 경로는 `/deployments/{id}/...` 유지 | 승인·취소·재시도·롤백·배포 SSE 연결 (다음 작업) |
| ② 설정 변경 시 409 | 동의. 바뀐 설정으로 진행하려면 새 배포 | 확정 |
| ③ `recordBuild` | 동의. 기존 빌드를 확인하고 저장값 반환, 새 빌드 등록과 별개 | 확정 |
| ④ 빌드 결과 저장 | 승환 제안: Jenkins 결과 수신·검증은 승환, `source_version` 등록은 은현 관리 서비스 | 수락 (10/2). 결과에 `project_id` 포함 여부·중복 기준·`build.received` 이벤트 3가지를 승환님께 확인 중 |
| ⑤ `disconnected` 409 | 동의. `unknown` 은 허용하되 연결 성공으로 표시하지 않음 | 확정 |
| ⑥ 재시도 경로 | 승환·승준·도영 동의 | 확정 `POST /deployments/{id}/retry` |

- **A-02 대상별 처리에서 권한 404 를 구분합니다.** 리뷰 지적대로 예전 재조회 방식은 권한 재검사의 404 를 대상 문제로 숨길 수 있었습니다. 승환의 `currentByTarget()`(044a436)으로 바꾸고 재조회 처리를 지웠습니다. 권한 오류는 조회 서비스가 그대로 올립니다.
- **생성 응답 이름을 소비자 모델에 맞췄습니다.** `deployment_id`·`status` → `id`·`state`, `project_id` 추가.

### 10/2 오전 점검 반영

- **요청 하나의 대상 수를 50개로 막습니다.** 생성·취소·재시도·롤백의 `target_ids` 와 승인의 `items` 가 50개를 넘으면 400 입니다. 실행 서비스가 프로젝트 행을 잠근 채 대상을 확인하므로, 잠그기 전에 공개 경로에서 끊습니다. 50 은 데모 대상(3개)보다 넉넉하게 잡은 값입니다.
- **A-02 `connection_state` 를 WR-04 와 같은 값(`ok`·`failed`·`unknown`)으로 바꿨습니다.** 계약에 없던 필드를 제가 더하면서 DB 값을 그대로 내보냈던 것입니다.
- 확인: 빈 PostgreSQL 17 에 jar 로 띄워 확인했습니다. A-02 가 DB `connected`·`disconnected`·`unknown` 을 `ok`·`failed`·`unknown` 으로 내보내고 대상마다 WR-04 와 같음. 생성 51개 400, 50개는 상한을 지나 다음 검사(없는 대상 404), 1개는 201. 승인 `items` 51개, 취소·재시도·롤백 51개 모두 400. A-04·A-03 200, 서버 로그 ERROR 0건.

### 승인 성공 확인 — DB 픽스처 (10/2 낮, 승환님 #42 리뷰)

실제 Jenkins E2E 와 따로, 빈 PostgreSQL 17 에 jar 를 띄우고 배포는 API 로 만든 뒤 plan·승인·스크립트 행을 SQL 로 넣어 확인했습니다. 승인 요청 `items` 는 A-04 `pending_approvals` 를 그대로 보냈습니다.

| | 검사 | 결과 |
|---|---|---|
| A1 | viewer 승인 | 403 |
| A2 | 대상 둘 다 승인 대기인데 하나만 보냄 | 409 (승인 대기 전체와 같아야 함) |
| A3 | A-04 `pending_approvals` 그대로 승인 | 202, 승인 행 둘 다 `approved`, apply 실행 1건 |
| A4 | 같은 `Idempotency-Key` 재전송 | 같은 202 응답, apply 실행 여전히 1건 |
| A5 | 삭제 포함 plan: 확인 문구 없음 / 틀림 / 프로젝트 이름 | 400 / 400 / 202 |
| A6 | 거절 | 202, 승인 행 `rejected`, 배포 `cancelled`, apply 실행 0건 |
| A7 | 기한 지난 승인만 있는 대상 | A-04 `pending_approvals` 에서 빠짐, 그 ID 로 승인 409 |

서버 로그 ERROR 0건. 픽스처를 맞추면서 실행부 조건 두 가지를 확인했습니다. 실제 수신부가 같은 값을 넣는지 연동 때 같이 봐야 합니다.

- 승인 기한은 plan 기한 이하여야 apply 명령이 만들어집니다. 처음 픽스처는 plan·승인을 따로 넣어 `now()` 가 몇 ms 달라 409 가 났습니다.
- 거절하려면 그 대상의 plan 을 만든 prepare 실행이 끝난 상태여야 합니다.

승인 직후 배포·대상 상태는 apply 실행이 시작될 때까지 `awaiting_approval` 그대로이고 `pending_approvals` 만 비어 있습니다. 화면에서는 "승인 대기인데 승인할 것이 없음" 으로 보일 수 있어 승환님께 여쭤봤습니다.

### 구현 상태 (10/2 새벽)

| | 무엇 | 위치 | 상태 |
|---|---|---|---|
| ① | `ExecutionAccess` 어댑터 | `project/access/ExecutionAccessAdapter` | 완료 |
| ② | `ExecutionInputs` 어댑터 | `project/execution/ExecutionInputsAdapter` | 완료. 확인 ②·⑤ 는 제안대로 넣고 메서드 하나씩으로 분리 |
| ③ | `POST /projects/{id}/deployments`·`GET /projects/{id}/events` | `project/web/DeploymentRequestController` | 완료 |
| ③ | `/deployments/{id}/...` 경로 (승인·취소·재시도·롤백·배포 SSE) | `project/web/DeploymentCommandController` | 완료 (`projectIdOf` 사용) |
| ④ | 승인 요청 변환 | `project/web/ApprovalRequest` | 완료 (컨트롤러는 ③ 대기) |
| ⑤ | A-02 `current`·A-06 `deployed_to` | `project/application/DeploymentHistoryReader` | 완료 |

공개 API 코드는 `server/AGENTS.md` §3 의 폴더 소유대로 `deployment/` 가 아니라 `project/` 에 둡니다.

**실측 (빈 PostgreSQL 17, jar 기동, Jenkins 워커 꺼진 기본 설정)**

| | 검사 | 결과 |
|---|---|---|
| C1 | `Idempotency-Key` 없음 | 400 |
| C2 | viewer 생성 | 403 |
| C3 | 정상 생성 (대상 2개) | 201 `{id, project_id, state: "queued"}` (#42 리뷰 뒤 이름 변경, 재기동으로 다시 확인). 입력 스냅샷 `{strategy: recreate, hash_format_version: 1}`, 저장소 스냅샷 키 5개, 대상 스냅샷의 자격증명은 참조 문자열 그대로. prepare 명령은 `pending` 으로 저장만 됨 |
| C4 | 같은 키·같은 본문 재전송 | 첫 응답 그대로, 배포 행 늘지 않음 |
| C5 | 같은 키·다른 본문 | 409 |
| C6 | `commit` 이 빌드와 다름 / 같음 | 400 / 201 |
| C7 | 없는 빌드 | 404 |
| C8 | `disconnected` 대상 | 409 |
| C9 | `strategy: canary` | 400 |
| S1 | 토큰 없이 SSE | 401 |
| S2 | SSE + `Last-Event-ID: 0` | 200 `text/event-stream`·`Cache-Control: no-cache`, heartbeat 뒤 `deployment.created` 두 건을 seq 1·2 로 재생 |
| S3 | 잘못된 `event_type` | 400 |
| O1 | OpenAPI | 두 경로·`Idempotency-Key`·`Last-Event-ID`·Bearer 요구가 나오고 `principal` 노출 0건 |

**배포 ID 경로 실측 (10/2 새벽, 같은 조건)** — 승인 성공(202)은 plan·승인 대기 행이 있어야 해서 Jenkins 결과 수신 뒤에 봅니다. 여기서는 실행 서비스까지 정확히 전달되고 판정을 그대로 돌려주는지 봤습니다.

| | 검사 | 결과 |
|---|---|---|
| D1 | 멱등 키 없음 | 400 |
| D2 | 없는 배포 | 404 (`projectIdOf`) |
| D3 | viewer 승인·취소 | 403 / 403 |
| D4 | `decision: "approved"`·빈 `items` | 400 / 400 |
| D5 | 승인 대기가 아닌 배포에 승인 | 409 |
| D6 | Jenkins 에 아직 안 나간 배포 취소 | 202 `{id, project_id, state: "cancelled"}` |
| D7 | 같은 키로 취소 재전송 | 첫 응답 재생 |
| D8 | 취소된 배포 재시도·롤백 / 롤백 사유 없음 | 409·409 / 400 |
| D9 | 배포 SSE 토큰 없음·없는 배포·정상 | 401·404·200 (`deployment.created`·`target.status_changed` 2건·`deployment.completed` 재생) |
| D10 | OpenAPI | 다섯 경로, 재시도 summary 에 (가칭), `principal` 노출 0건 |

500 은 0건이었습니다. 처음에 롤백이 400 으로 나온 것은 검증 명령(Git Bash 가 한글을 UTF-8 이 아닌 바이트로 보냄) 때문이었고, UTF-8 로 다시 보내 409 를 확인했습니다.

### 확인이 필요한 것 (승환)

**① `/deployments/{id}/...` 경로에서 `projectId` 를 어떻게 얻을까요.** 실행 서비스는 모든 요청에 `projectId` 를 받는데, 공개 경로에는 배포 ID 만 있습니다. 배포 → 프로젝트 조회는 `deployment` 모듈 소유라 제가 직접 읽지 않으려고 합니다. `EventJournal.requireDeploymentProject(projectId, deploymentId)` 는 둘 다 알 때 맞는지만 봅니다. **`deployment` 쪽에 `projectIdOf(deploymentId)` 같은 조회를 하나 열어 주실 수 있을까요.** 없는 배포는 404 로 하면 됩니다. 이게 없으면 경로를 `/projects/{pid}/deployments/{id}/...` 로 바꿔야 해서 웹·앱 계약이 바뀝니다.

**② 재시도·롤백 때 대상 설정이 바뀌었으면 막을까요.** `verifyFrozen` 에서 `config_revision`·`credential_version` 이 고정 값과 다를 때 두 길이 있습니다.

| | 동작 | 결과 |
|---|---|---|
| 가 | 409 로 막는다 | 옛 설정으로 apply 하지 않는다. 사용자는 새 배포를 만들어야 한다 |
| 나 | 허용한다 | 재시도는 "같은 입력 그대로" 라는 계약과 맞다. 대신 지금 설정과 다른 것이 적용된다 |

저는 **가** 쪽이 안전하다고 봅니다. 고정 입력을 재사용하는 게 재시도의 정의라면, 그 입력이 이미 낡았을 때 조용히 쓰는 것보다 막는 게 낫다고 생각합니다. 어느 쪽이 맞을까요.

**③ `recordBuild` 가 `source_version` 에 무언가를 써야 할까요.** 인터페이스 주석은 *"before recording the build"* 인데, `capture` 가 이미 성공 빌드만 받기 때문에 `bindBuildResult` 시점에는 그 빌드가 DB 에 있다고 봤습니다. 그래서 위 스펙은 **확인만 하고 쓰지 않습니다.** PREPARE 가 새 빌드를 만들어 그 결과를 여기서 기록해야 하는 흐름이 있다면 알려 주세요.

**④ Jenkins 빌드 결과를 `source_version` 에 넣는 쪽은 누구일까요.** A-06 빌드 목록과 ② 의 `capture` 가 모두 이 행을 전제로 합니다. #40 의 결과 수신 기준에 들어가는지, 제가 수신 경로를 따로 만들어야 하는지 정해야 합니다.

**⑤ `disconnected` 대상을 생성에서 막을까요.** W-04 가 *"연결 안 되는 환경은 고를 수 없어요"* 인데, 지금은 연결 확인 기능이 없어서 모든 대상이 `unknown` 입니다. `unknown` 까지 막으면 아무것도 배포할 수 없습니다. **`disconnected` 만 409 로 막고 `unknown` 은 허용**하는 쪽을 제안합니다.

**⑥ 재시도를 어느 경로로 받을까요 (웹·앱과 함께).** 승환은 #13 에서 *"실패한 환경 재시도는 기존 답변대로 새 배포"*, *"재시도의 원본 연결 등 구체 요청은 공개 API에서 맞추겠습니다"* 라고 했습니다. 웹·앱 명세는 WR-05(새 배포 생성)를 그대로 씁니다. 실행 서비스에는 원본 배포에서 실패 대상만 복사하는 `retry` 가 따로 있습니다. 계보(lineage)가 남는 `retry` 를 쓰려면 `POST /deployments/{id}/retry` 를 새로 열어야 하고 웹·앱 호출도 바뀝니다. **저는 `retry` 경로를 여는 쪽을 제안합니다** — 실패 대상만 고르고 원본 성공 대상을 건드리지 않는 규칙을 서버가 보장할 수 있어서입니다.

### 다른 파트와 닿는 지점

| 누구 | 무엇 |
|---|---|
| 승환 | 위 ①~⑤. ① 이 정해져야 ③ 의 경로가 확정됩니다 |
| 웹·앱 | WR-05 에 `source_version_id` 가 필수로 더해집니다 (S1, A-06 이 이미 내보냄. 웹은 수용). 승인 요청에 `items[]` 가 더해지고 **비면 400** 입니다 (S4). 승인 ID 는 A-04 `pending_approvals` 로 줍니다 (#40 승준). **A-02 `current: null` 은 "배포 없음"이 아니라 "확인된 참조 없음"** 이라 화면 문구를 바꿔야 합니다. 재시도 경로는 ⑥ 에서 함께 정합니다 |
| 인프라 | 없음. Jenkins 연결은 #35 에서 승환이 맞춥니다 |

### 검증 계획 (구현 뒤)

검사 항목을 먼저 적고 그대로 돌립니다.

| | 검사 | 기대 |
|---|---|---|
| V1 | `ExecutionAccess` — 없는 프로젝트·비멤버·철회 멤버십·`viewer` 쓰기·비활성 계정 | 404·404·404·403·401 |
| V2 | `capture` — 다른 프로젝트 빌드·`running` 빌드·`image_refs` commit 불일치·다른 프로젝트 대상·보관 대상·`input` 에 `hash_format_version` | 404·409·409·404·404·400 |
| V3 | `capture` 반환값에 비밀값이 없다 — `credential_*` 는 참조 문자열 그대로 | 통과 |
| V4 | `verifyFrozen` — 대상 보관·`state_identity` 변경·빌드 상태 변경 | 409 |
| V5 | `recordBuild` — `sourceVersionId` 없음·commit 불일치·`image_refs` 없음 | 409, NPE 없음 |
| V6 | 승인 변환 — `decision: "approved"`·중복 `target_id`·빈 `items`·`kind: "deploy"` | 400 |
| V7 | `Idempotency-Key` 없는 POST | 400 |
| V8 | 같은 키로 같은 요청 두 번 | 첫 응답 그대로 재생 |
| V9 | 실제 기동 — 로그인 → 생성 → 승인 → SSE 연결·`Last-Event-ID` 재연결 | 각 단계 상태 코드와 이벤트 seq |
| V10 | OpenAPI — 새 경로 전부 Bearer 요구, `principal` 쿼리 노출 0건 | 통과 |
| V11 | A-02 — 포인터 없음·정상 포인터·다른 대상을 가리키는 포인터가 섞인 프로젝트 | 각각 `none`·채워짐·`unverified`, **응답 전체는 200** |
| V12 | A-06 — 성공 이력 있는 빌드·없는 빌드 | `deployed_to` 채워짐·`[]` |
| V13 | `./gradlew --no-daemon spotlessCheck check build` | 성공 |

V9 의 실제 Jenkins 실행은 하지 않습니다. 기본 비활성 설정 그대로 명령이 저장되는 데까지만 봅니다.

## 배포 대상 목록 WR-04 (10/2, 하은현)

### 범위

`GET /projects/{id}/targets` 는 배포 시작 화면(W-04)과 환경 화면(W-10)에서 고를 수 있는 대상 목록을 돌려줍니다. A-02(`targets/status`)와 별도 경로로 두는 것은 9/30 결정(*"환경 선택용 `GET /projects/{id}/targets`는 `targets/status`와 별도"*, PR #9)대로입니다. A-02 는 "지금 어떻게 떠 있나", WR-04 는 "어디에 배포할 수 있나" 입니다.

- 권한은 A-02 와 같습니다. `ProjectAccessService.requireRead` — 없는 프로젝트·비멤버 404, viewer 도 조회는 됩니다.
- 보관된 대상은 뺍니다. 정렬은 A-02 와 같은 `(environment_type, name)` 입니다.
- 목록 봉투 `{ items, next_cursor }` 이고 `next_cursor` 는 항상 null 입니다 (프로젝트당 대상이 몇 개뿐).
- 이번 범위가 아닌 것: W-10 의 선택 필드(`title`·`runtime`·`location`·`access_method`·`exposure`·`state_backend`·`current_commit`). 대상 설정 키가 정해지지 않았고 S8 에서 `title` 조립 주체도 미정입니다.

### 응답 필드

소비자 계약은 `ios/SPEC.md` 406행 *"`target_id, type, name, reuse{ available, script_id?, reason? }, connection{ state: ok·failed·unknown, checked_at }`"* 입니다.

| 필드 | 출처 | 비고 |
|---|---|---|
| `target_id`·`type`·`name` | `target.id`·`environment_type`·`name` | A-02 와 같음 |
| `connection.state` | `target.connection_state` 를 변환 | 아래 표 |
| `connection.checked_at` | `target.connection_checked_at` | 확인한 적 없으면 null |
| `reuse` | `target.reuse_assessment` | **인프라 보고가 없으면 통째로 null** |
| `reuse.available`·`script_id`·`reason` | 같은 JSON 의 같은 키 | |
| `reuse.assessed_at` | 같은 JSON 의 `assessed_at` | 설계의 "판정 시각". 키 이름은 인프라 보고 형식이 정해지면 맞춥니다 |

**연결 상태는 소비자 값으로 바꿉니다.** S1 의 *"DB enum을 API에 그대로 노출하지 않습니다"* 를 따릅니다.

| DB `ck_target_conn` | WR-04 `connection.state` |
|---|---|
| `connected` | `ok` |
| `disconnected` | `failed` |
| `unknown` | `unknown` |
| 그 밖 | 그대로 (꾸미지 않음) |

**`reuse` 는 없으면 null 입니다.** 인프라가 재사용 판정을 보고한 적이 없는데 `available: false` 로 보내면 "재사용 불가로 확인됨" 처럼 읽힙니다. 지금은 `reuse_assessment` 를 채우는 곳이 없어서 항상 null 입니다. 저장된 JSON 이 모양과 다르면(`available` 이 boolean 이 아님 등) 목록 전체를 실패시키지 않고 그 대상의 `reuse` 만 null 로 둡니다.

### 확인이 필요한 것

**① A-02 의 `connection_state` 와 값이 다릅니다 (웹·앱).** A-02 는 계약에 없던 필드를 제가 더하면서 DB 값(`connected`·`disconnected`)을 그대로 내보냈고, 웹은 *"W-04에서 연결이 안 되는 환경을 막을 때는 `connection_state`를 쓸게요"* (#38 도영) 라고 했습니다. W-04 는 원래 WR-04 를 쓰는 화면이라, **W-04 에서는 WR-04 `connection.state` 를 써 달라고** 알리겠습니다. A-02 값도 같은 변환으로 맞출지는 웹·앱과 정합니다. → 10/2: A-02 도 같은 변환으로 맞췄습니다. 두 화면이 같은 값을 쓰게 하는 쪽이 낫다고 봤고, 웹·앱에 알립니다.

**② `reuse_assessment` 를 채우는 쪽 (승환·인프라).** 설계는 *"인프라가 보고한"* 값인데 수신 경로가 없습니다. 실행 결과 수신(#35)과 함께 정해지면 키 이름도 맞춥니다.

### 검증 계획

| | 검사 | 기대 |
|---|---|---|
| T1 | 토큰 없음 / 비멤버 / viewer | 401 / 404 / 200 |
| T2 | `connected`·`disconnected`·`unknown` 대상 | `ok`·`failed`·`unknown` |
| T3 | `reuse_assessment` 없음 / 정상 / 모양 틀림 | null / 채워짐 / 그 대상만 null, 응답 200 |
| T4 | 보관된 대상 | 목록에 없음 |
| T5 | OpenAPI | 경로가 나오고 `principal` 노출 0건 |

### 검증 결과 (10/2 새벽)

빈 PostgreSQL 17 에 jar 로 기동해서 확인했습니다. 단위 테스트 4개(변환 규칙)도 추가했습니다.

| | 결과 |
|---|---|
| T1 | 토큰 없음 401, viewer 200, 멤버십 철회 뒤 404 |
| T2 | `connected`→`ok`, `disconnected`→`failed`, `unknown`→`unknown`. 확인한 적 없는 대상은 `checked_at: null` |
| T3 | 판정 없음 → `reuse: null`, 정상 판정 → 네 필드 그대로, `available: "yes"` 처럼 모양이 틀린 판정 → 그 대상만 `reuse: null`, 응답은 200 |
| T4 | 보관된 대상은 목록에 없음 |
| T5 | OpenAPI 에 경로가 나오고 파라미터는 `projectId` 하나 (`principal` 노출 없음) |

## 배포 상세 A-04 (10/2, 하은현)

### 범위

`GET /deployments/{id}` 는 배포 한 건의 스냅샷을 돌려줍니다. 웹·앱의 배포 진행·승인·결과 화면이 이걸로 상태를 그리고, 승인할 때 보낼 `approval_id` 를 `pending_approvals` 에서 얻습니다 (#40 승준, #42).

- 권한: `projectIdOf(actorId, deploymentId)` (044a436). 없는 배포·접근할 수 없는 배포는 404, viewer 도 조회는 됩니다.
- 데이터: `server/AGENTS.md` §3 예외대로 `deployment`·`deployment_target`·`approval` 을 읽기 전용 SQL 로 직접 읽습니다. 쓰지 않습니다.
- 소비자 모델: `ios/SPEC.md` 326행 `Deployment`, 웹 `web/src/api/types.ts` `Deployment`.

### 응답 필드

| 필드 | 출처 | 비고 |
|---|---|---|
| `id`·`project_id` | `deployment.id`·`project_id` | |
| `source_version_id`·`commit` | `deployment.source_version_id`·`commit_sha` | |
| `image`·`image_digest`·`images` | `deployment.image_refs` | 배포를 만들 때 고른 성공 빌드의 이미지. 서비스가 하나면 scalar, 여럿이면 scalar null + `images[]` (S5, A-06 과 같은 규칙). 값이 없으면 전부 null |
| `state` | `deployment.status` | 배포 전체 7값 그대로 (계약과 코드값이 같음) |
| `kind` | `deployment.kind` | `rollback` 이면 `"rollback"`, 아니면 null. `normal`·`retry` 는 내부 값이라 내보내지 않음 (AGENTS §5) |
| `rolled_back_from` | `deployment.rollback_of_deployment_id` | 설계 6장 매핑 |
| `retry_of` | `deployment.retry_of_deployment_id` | 계약에 없던 필드. 재시도 화면이 원본으로 돌아갈 때 쓸 수 있게 둠 |
| `targets[]` | `deployment_target` | 아래 표. 정렬은 `target_id` |
| `pending_approvals[]` | `approval` (`state='pending'`) | `{ target_id, approval_id }`. 승인 요청 `items` 와 같은 모양. 없으면 `[]` |
| `created_by` | `deployment.requested_by` → `account.display_name` | 계정이 없으면 계정 ID 그대로 |
| `created_at`·`finished_at` | 같은 이름 | |
| `last_seq` | `deployment.last_event_seq` | SSE 재연결 기준점 |

`targets[]`

| 필드 | 출처 | 비고 |
|---|---|---|
| `target_id` | `deployment_target.target_id` | |
| `type`·`name` | `target_snapshot` 의 `environment_type`·`name` | 배포 당시 고정값 |
| `state` | `deployment_target.status` | 대상별 9값 그대로 |
| `attempt` | `deployment_target.attempt` | **0 이면 null** (S2: "API null, DB 0 유지") |
| `reused_script` | `deployment_target.ai_reused` | |
| `error_summary` | 같은 이름 | |
| `cancel_requested_at` | 같은 이름 | 취소 요청이 접수됐지만 아직 끝나지 않은 상태를 보여 줄 수 있게 둠 |
| `started_at`·`finished_at` | 같은 이름 | |
| `step`·`step_state`·`url`·`image_digest`·`health_summary` | — | **null.** `url`·`image_digest`·`health_summary` 는 근거 데이터가 아직 없음 (apply 결과 수신 #35 대기). `step`·`step_state` 는 승환님 Jenkins 수신이 `deployment_log` 에 `step.started`·`completed`·`failed` 로 남기지만 아직 읽지 않음 — A-07 로그 조회와 함께 붙임 (10/2 점검에서 정정). 0·빈 값으로 채우지 않음 |

내보내지 않는 것: `version`("v7")·`commit_message` 는 S8 후순위, 단건 `pending_approval` 은 `pending_approvals` 로 대체 (#40 승준 질문에 답한 대로).

### 검증 계획

| | 검사 | 기대 |
|---|---|---|
| Q1 | 토큰 없음 / 없는 배포 / 비멤버 / viewer | 401 / 404 / 404 / 200 |
| Q2 | 막 만든 배포 (대상 2개) | `state: "queued"`, 대상 2개 `waiting`, `attempt: null`, `pending_approvals: []`, 고른 빌드의 이미지 |
| Q3 | 승인 대기 행이 있는 배포 | `pending_approvals` 에 `{target_id, approval_id}`, 만료·처리된 승인은 빠짐 |
| Q4 | 롤백 배포 | `kind: "rollback"`, `rolled_back_from` 채워짐 |
| Q5 | 이미지가 고정된 배포 (서비스 1개 / 2개) | scalar / `images[]` |
| Q6 | 다른 프로젝트 배포가 섞이지 않음 | 경로의 배포 한 건만 |
| Q7 | OpenAPI | 경로가 나오고 `principal` 노출 0건 |

### 검증 결과 (10/2 오전)

단위 테스트 4개(승인 ID 옮김, `kind` 변환, 시도 0·근거 없는 필드 null, 이미지 단일·여럿·없음)를 추가했고, 빈 PostgreSQL 17 에 jar 로 띄워 확인했습니다.

| | 결과 |
|---|---|
| Q1 | 401 / 404 / 404(다른 프로젝트, Q6 와 같이 확인) / 200 |
| Q2 | `queued`, 대상 2개 `waiting`·`attempt: null`·`step: null`, `pending_approvals: []`, 고른 빌드의 이미지, `created_by: "데모 운영자"`, `last_seq: 1` |
| Q3 | 유효한 승인만 `[{tgt_demo_aws, apv_ok}]`. 만료 시각이 지난 pending 승인은 빠짐 |
| Q4 | `kind: "rollback"`, `rolled_back_from` 에 원본 배포 |
| Q5 | 서비스 2개면 `image: null`, `images[]` 2개 (digest 없는 서비스는 null 그대로) |
| Q6 | 접근 권한 없는 다른 프로젝트 배포는 404 |
| Q7 | 경로 노출, `principal` 0건. 500 0건 |

처음 스펙에는 "막 만든 배포는 이미지 null" 이라고 적었는데, 실제로는 생성 때 고른 성공 빌드의 이미지가 고정됩니다. 코드가 맞고 스펙을 고쳤습니다.

### 후속·통합 검증으로 남기는 것 (10/2 승환님 #46 리뷰)

- **일부 승인만 만료된 대상 / 전부 만료된 대상.** A-04 는 `state='pending'` 이고 기한이 남은 승인만 `pending_approvals` 로 줍니다. 그런데 실행 서비스의 승인은 `awaiting_approval` 인 대상 전체와 요청 `items` 가 같아야 통과합니다. 대상 A 는 유효하고 B 는 기한이 지났는데 아직 `awaiting_approval` 이면, A-04 응답 그대로 승인해도 409 입니다. 만료된 ID 를 다시 내보내거나 승인 검사를 느슨하게 하지 않고, 승환님 실행부가 만료 대상을 정리하도록 연결합니다(승환님 담당). 그 전까지 "A-04 의 승인 대기만 보내면 승인된다" 는 완료로 보지 않습니다. 연결 뒤 두 경우를 통합 검증에 넣습니다.
- **단계(`step`·`step_state`).** 두 가지를 나눠 둡니다. ① 저장된 `step.*` 이벤트를 읽는 조회 구현은 A-07 과 함께 제가 붙입니다. ② 실제 Jenkins 에서 그 이벤트가 들어오는 것은 #35 수신 대기입니다.

## 배포 목록 A-03 (10/2, 하은현)

### 범위

`GET /projects/{id}/deployments?state=&cursor=&limit=` 는 프로젝트의 배포를 최신순으로 돌려줍니다. 배포 이력(W-09)·현황(W-01)·AI 사용량 배포 고르기(W-12) 화면이 쓰고, 승인 대기 목록은 별도 API 없이 `state=awaiting_approval` 로 거릅니다 (9/29 결정, PR #1).

- 권한: `ProjectAccessService.requireRead` — 없는 프로젝트·비멤버 404, viewer 도 조회는 됩니다.
- 데이터: A-04 와 같이 배포 테이블을 읽기 전용 SQL 로 읽습니다 (`server/AGENTS.md` §3 예외).
- 봉투: `{ items, next_cursor }`. **목록 한 줄은 A-04 상세와 같은 모양**입니다. 웹은 목록을 `ListResponse<Deployment>` 로 받아서, 모양을 둘로 나누면 화면마다 다른 필드를 다뤄야 합니다.

### 동작

| 항목 | 규칙 |
|---|---|
| 정렬 | `created_at DESC, id DESC`. 설계의 `INDEX(project_id, created_at DESC, id)`·`INDEX(project_id, status, created_at DESC, id)` 와 맞춤 |
| `state` | 배포 전체 7값 중 하나. 다른 값은 400. 생략하면 전부 |
| `cursor` | A-06 과 같은 불투명 문자열 (base64url 로 감싼 `created_at` + `id`). 깨진 커서는 400. 같은 시각의 배포가 페이지 경계에 걸려도 건너뛰지 않음 |
| `limit` | 기본 20, 최대 100. 넘으면 100 으로 깎고, 0·음수는 400 (A-06 과 같음) |
| 대상·승인 대기 | 한 페이지의 배포 ID 로 `deployment_target`·`approval` 을 한 번씩만 읽음. 배포마다 따로 읽지 않음 |

### 검증 계획

| | 검사 | 기대 |
|---|---|---|
| L1 | 토큰 없음 / 비멤버 / viewer | 401 / 404 / 200 |
| L2 | 배포 3개 | 최신순, 각 항목이 A-04 모양 (대상·`pending_approvals` 포함) |
| L3 | `state=awaiting_approval` / `state=bogus` | 그 상태만 / 400 |
| L4 | `limit=2` 로 커서 왕복, 같은 `created_at` 두 건 포함 | 중복·누락 0, 마지막 페이지 `next_cursor: null` |
| L5 | 깨진 커서 / `limit=0` | 400 / 400 |
| L6 | 다른 프로젝트 배포 | 섞이지 않음 |
| L7 | OpenAPI | 경로·`state`·`cursor`·`limit` 노출, `principal` 노출 0건 |

### 검증 결과 (10/2 오전)

빈 PostgreSQL 17 에 jar 로 띄워, API 로 만든 배포 3개와 SQL 로 넣은 배포 4개(그중 2개는 `created_at` 이 똑같음), 다른 프로젝트 배포 1개로 확인했습니다.

| | 결과 |
|---|---|
| L1 | 401 / 404 / 200 |
| L2 | 7개 최신순, 각 항목이 A-04 모양 (대상 수·`pending_approvals` 포함) |
| L3 | `awaiting_approval` 은 그 1건만 / `bogus` 400 |
| L4 | `limit=2` 로 4페이지, 7개 모두, 중복 0, 전체 목록과 순서가 같음 (같은 시각 2건이 경계에 걸려도 빠지지 않음), 마지막 `next_cursor: null` |
| L5 | 구분자 없는 base64·base64 아닌 문자 커서 400 / `limit=0` 400 |
| L6 | 다른 프로젝트 배포가 섞이지 않음 |
| L7 | 파라미터 `state`·`cursor`·`limit`, `principal` 노출 0건. 500 0건. 조회 코드를 바꾼 뒤 A-04 상세도 200 |

URL 인코딩 자체가 깨진 커서(`%%%bad`)는 Tomcat 이 파라미터를 버려서 커서 없이 첫 페이지(200)가 나갑니다. A-06 도 같습니다. 서블릿 컨테이너 동작이라 따로 막지 않았습니다.

**회귀 테스트 (10/2, 승환님 #48 리뷰).** `DeploymentQueryPostgresTest` 가 실제 PostgreSQL 에서 같은 시각 배포 두 건이 페이지 경계에 걸리는 경우(첫 페이지가 `dep_c` 로 끝나고 다음 페이지가 같은 시각 `dep_b` 부터), 상태 필터, 다른 프로젝트가 섞이지 않는 것, 다른 프로젝트 배포 상세 404 를 고정합니다. `DAISY_TEST_DB_URL` 이 있을 때만 돕니다. 같은 시각 비교 조건을 빼면 커서 테스트 2개가 실패하는 것을 확인했습니다.

## 배포 plan 조회 A-05 · WR-06 (10/2, 하은현)

### 범위

승인 화면(W-06)이 대상별 변경 개수·삭제 여부·위험 설정과 이 배포의 AI 사용량 합계를 읽습니다.

| 경로 | 응답 | 소비자 모델 |
|---|---|---|
| `GET /deployments/{id}/plan` | `{ deployment_id, targets[], ai_usage }` | `ios/SPEC.md` `Plan`, `web/src/api/types.ts` `Plan` |
| `GET /deployments/{id}/plan?detail=resources` | `[{ target_id, resources[], plan_text }]` (배열) | `web/src/api/types.ts` `PlanDetail[]` (WR-06) |

- 권한: A-04 와 같이 승환님 `projectIdOf` 로 봅니다. 없는 배포·접근할 수 없는 배포는 404, viewer 도 조회는 됩니다.
- 데이터: `deployment_target.current_plan_id` 가 가리키는 `plan_revision` 과 `ai_usage` 를 읽기 전용 SQL 로 읽습니다 (`server/AGENTS.md` §3 예외에 두 테이블이 이미 들어 있음). 상태를 바꾸지 않습니다.
- `detail` 은 `resources` 만 받습니다. 다른 값은 400 입니다. 같은 경로에서 응답 모양이 둘인 것은 9/30 WR-06 답("그대로")과 웹 코드를 따른 것입니다.

### 대상 한 줄

| 필드 | 출처 | 비고 |
|---|---|---|
| `target_id` | `deployment_target.target_id` | |
| `counts` | `plan_revision.summary.counts` | `{create, update, delete}`. 승환님 `PlanRevision` 이 저장 전에 모양을 검증함 |
| `has_delete` | `summary.has_delete` | 교체(replace)로 생긴 삭제도 포함 |
| `risks` | `summary.risks` | `[{level, rule, resource, message}]` 그대로 |
| `summary` | 없음 | **null.** 한 줄 요약을 만드는 원천이 없음. 화면은 "위험 설정 n건" 으로 대신함 |
| `plan_text` | 없음 | **null.** 서버는 원본 참조(`artifact_ref`)·digest 만 갖고 원문을 보관하지 않음 |

- **현재 plan 이 있는 대상만** 나옵니다. 아직 plan 전이거나, 새 plan 으로 바뀌는 중이라 포인터가 비어 있는 대상은 빠집니다. 승인할 대상과 approval ID 는 A-04 `pending_approvals` 가 기준입니다.
- 정렬은 `target_id` 순입니다.

### `resources` (WR-06)

`plan_revision.resources` 의 `{address, actions[]}` 를 웹 모양 `{address, action}` 으로 바꿉니다.

| `actions` | `action` |
|---|---|
| `delete` 와 `create` 를 함께 가짐 (순서 무관) | `replace` |
| `delete` 를 가짐 | `delete` |
| `create` 를 가짐 | `create` |
| `update` 를 가짐 | `update` |
| `read`·`no-op` 만 | 목록에서 뺌 (바뀌는 것이 아님. `counts` 에도 안 들어감) |

`monthly_cost_krw` 는 원천이 없어 넣지 않습니다.

### `ai_usage` 합계

이 배포에 속한 모든 대상·회차의 `ai_usage` 행을 더합니다. 설계 5.13 과 9/29 결정을 따릅니다.

| 필드 | 규칙 |
|---|---|
| `calls` | 행 수 (LLM 호출 수). 상태 `succeeded`·`failed`·`unknown` 모두 셈 |
| `tokens` | 입력·출력 토큰을 둘 다 아는 행의 합. 그런 행이 없으면 null |
| `cost_krw` | `cost_usd` 를 아는 행의 USD 합 × 고정 환율, 원 단위 반올림(HALF_UP). 아는 행이 없거나 환율 설정이 없으면 null |
| `exchange_rate` | 설정값 `daisy.ai.krw-per-usd` (환경변수 `DAISY_AI_KRW_PER_USD`). 없으면 null |
| `estimated` | `cost_krw` 가 있으면 true (고정 환율 환산이라 늘 추정). 없으면 false |
| `unknown_calls` | 토큰이나 비용을 모르는 행 수. 설계 5.13 "미확인 호출 수" — 계약에 없는 추가 |

- **행이 없으면 `calls: 0`, `tokens`·`cost_krw` 는 null 입니다.** 지금 Jenkins `plan-summary.json` 은 합계만 주고 호출별 기록을 주지 않아서, 행이 없다는 것이 "AI 를 안 썼다" 는 뜻이 아닐 수 있습니다. 0원으로 보여주지 않습니다.
- 환율 숫자는 아직 정하지 않았습니다 (`server/AGENTS.md` 남은 결정 "적용 환율 숫자"). 승환님께 여쭤봤고, 정해질 때까지 설정이 없으면 원화는 null 입니다. 0 이하·숫자가 아닌 값이면 기동하지 않습니다.

### 다른 파트와 닿는 지점

- 웹 `AiUsageSummary.exchange_rate` 가 `number` 입니다. 환율이 설정되지 않으면 null 이 갑니다.
- 웹 `PlanDetail.resources[].action` 에 `replace` 가 있어서 그대로 맞췄습니다.

### 검증 계획

| | 검사 | 기대 |
|---|---|---|
| P1 | 토큰 없음 / 없는 배포 / viewer | 401 / 404 / 200 |
| P2 | plan 없는 배포 | `targets: []`, `ai_usage.calls: 0`, `tokens`·`cost_krw` null |
| P3 | 대상 2개 중 1개만 현재 plan | 그 1개만, `counts`·`has_delete`·`risks` 가 저장값 그대로, `summary`·`plan_text` null |
| P4 | `detail=resources` | 배열. `["delete","create"]`→`replace`, `["no-op"]` 빠짐 / `detail=bogus` 400 |
| P5 | 사용량 행 3개 (하나는 토큰·비용 미확인), 환율 설정 | `calls 3`, `unknown_calls 1`, 토큰·원화는 아는 행만, USD 합 후 한 번 반올림 |
| P6 | 환율 설정 없음 | `cost_krw`·`exchange_rate` null, `estimated false` |
| P7 | 다른 프로젝트 배포의 plan·사용량 | 섞이지 않음, 404 |
| P8 | OpenAPI | 경로 노출, `principal` 노출 0건, 500 0건 |

### 검증 결과 (10/2 오전)

빈 PostgreSQL 17 에 jar 로 띄우고, API 로 만든 배포(대상 2개)에 SQL 로 실행·스크립트·plan 1건(대상 하나만 현재 plan)과 사용량 3행을 넣어 확인했습니다. 환율은 `DAISY_AI_KRW_PER_USD=1400` 으로 한 번, 설정 없이 한 번 띄웠습니다.

| | 결과 |
|---|---|
| P1 | 401 / 404 / viewer 200 |
| P2 | plan 전 배포: `targets: []`, `calls: 0`, `tokens`·`cost_krw` null, `estimated: false` |
| P3 | 현재 plan 이 있는 `tgt_demo_aws` 1개만. `counts {12,1,1}`·`has_delete: true`·`risks` 가 넣은 값 그대로, `summary`·`plan_text` null |
| P4 | `detail=resources` 는 배열. `create`·`update` 그대로, `["delete","create"]` → `replace`, `read`·`no-op` 행은 빠짐. `detail=bogus` 400 |
| P5 | `calls 3`, `unknown_calls 1`, `tokens 3920`(모르는 행 제외), `cost_krw 1`. 0.0003 USD 두 건이라 건별 반올림이면 0원, 합산 뒤 반올림이면 0.84원 → 1원 — 합산 뒤 한 번 반올림하는 것을 확인 |
| P6 | 환율 설정 없음: `cost_krw`·`exchange_rate` null, `estimated: false`. 사용량은 있는데 환율만 없는 경우는 단위 테스트(`PlanResponseTest`)로 확인 |
| P7 | 접근할 수 없는 다른 프로젝트 배포는 요약·`detail` 모두 404. 같은 프로젝트의 다른 배포에는 위 plan·사용량이 섞이지 않음 |
| P8 | OpenAPI 경로 노출, `detail` 은 선택 파라미터, 응답은 `PlanResponse` 또는 `PlanDetailResponse[]`, `principal` 노출 0건. 서버 로그 ERROR 0건 |

단위 테스트 7개를 더했습니다 (환산·반올림·잘못된 환율 3개, 응답 변환 4개). `./gradlew --no-daemon spotlessCheck check build` 성공, 182개 통과.

같은 경로의 두 핸들러가 OpenAPI 에서 한 operation 으로 합쳐지면서 처음에는 `detail` 이 필수로 표시됐습니다. 붙이지 않는 A-05 호출이 있으니 문서에서 선택으로 보이게 고쳤습니다.

## AI 호출별 기록 WR-11 (10/2, 하은현)

### 범위

`GET /projects/{id}/ai-usage?deployment_id=` 로 배포 한 건의 AI 호출 기록을 줍니다 (W-12). 합계는 A-05 `ai_usage` 가 맡고, 여기는 호출 한 줄씩입니다 (#13, 승환님 `docs/sh/2026-10-01-pr19-feedback.md` S3).

- 권한: `requireRead`. 비멤버·없는 프로젝트 404, viewer 200.
- `deployment_id` 는 필수입니다. 없으면 400, 그 프로젝트의 배포가 아니면 404 입니다.
- 데이터: `ai_usage` 를 읽기 전용 SQL 로 읽습니다 (`server/AGENTS.md` §3 예외). 대상 소속은 `deployment_target` 으로 확인합니다.
- 봉투 `{ items, next_cursor }`. 한 배포의 호출은 대상당 많아야 몇 번이라 한 번에 주고 `next_cursor` 는 null 입니다. 넘칠 때를 대비해 1000 행까지만 줍니다.
- 순서: 호출 시각(`occurred_at`), 같은 시각이면 ID 순.

### 한 줄

| 필드 | 출처 | 비고 |
|---|---|---|
| `at` | `occurred_at` | |
| `deployment_id` | `deployment_target.deployment_id` | |
| `target_id` | `deployment_target.target_id` | |
| `step` | `step` | `generate`·`fix` 등 원천 값 그대로 |
| `attempt` | `attempt` | 1~3 |
| `tokens` | `input_tokens + output_tokens` | 둘 중 하나라도 모르면 null. 0 으로 만들지 않음 |
| `cost_krw` | `cost_usd` × 고정 환율, 원 단위 반올림(HALF_UP) | 비용을 모르거나 환율 설정이 없으면 null |
| `status` | `status` | LLM 호출 결과 `succeeded`·`failed`·`unknown` 그대로 (Terraform 검증 결과 아님) |
| `note` | 없음 | null. 원본 설명이 오면 채움 |

- 줄마다 원화로 반올림하므로, 줄의 `cost_krw` 를 더한 값은 A-05 합계(USD 를 먼저 더한 뒤 한 번 반올림)와 1~2원 다를 수 있습니다. 합계는 A-05 를 기준으로 봅니다.
- 지금 Jenkins 는 호출별 기록을 주지 않아서 대부분 빈 목록입니다. 빈 목록을 "AI 를 안 썼다" 로 보여주지 않게 웹·앱에 알립니다.

### 검증 계획

| | 검사 | 기대 |
|---|---|---|
| U1 | 토큰 없음 / 비멤버 프로젝트 / viewer | 401 / 404 / 200 |
| U2 | `deployment_id` 없음 / 다른 프로젝트 배포 / 없는 배포 | 400 / 404 / 404 |
| U3 | 호출 3행 (하나는 토큰·비용 모름, 하나는 출력 토큰만 모름) | 시각 순, `tokens`·`cost_krw` 는 아는 줄만, 나머지 null |
| U4 | 환율 1400, 0.0003 USD | `cost_krw` 0 (0.42원 반올림) |
| U5 | 같은 프로젝트 다른 배포의 호출 | 섞이지 않음 |
| U6 | OpenAPI | 경로·`deployment_id` 노출, `principal` 0건, 서버 로그 ERROR 0건 |

### 검증 결과 (10/2 낮)

단위 테스트 2개(줄 변환·환율 없음)와, 빈 PostgreSQL 17 에 jar 로 띄운 실서버(`DAISY_AI_KRW_PER_USD=1400`)로 확인했습니다. API 로 만든 배포 2개에 호출 4행을 SQL 로 넣었습니다.

| | 결과 |
|---|---|
| U1 | 토큰 없음 401 / 비멤버 프로젝트 404 / viewer 200 |
| U2 | `deployment_id` 없음 400 / 다른 프로젝트 배포 404 / 없는 배포 404 |
| U3 | 시각 순 3줄. 토큰·비용 모르는 줄은 둘 다 null, 출력 토큰만 모르는 줄은 `tokens: null`·`cost_krw: 48` |
| U4 | 0.0003 USD → `cost_krw: 0`, 0.0343 USD → 48 |
| U5 | 같은 프로젝트 다른 배포의 호출은 그 배포에서만 보임 |
| U6 | 파라미터 `projectId`·`deployment_id`, `principal` 0건, 서버 로그 ERROR 0건 |

`./gradlew --no-daemon spotlessCheck check build` 성공.
