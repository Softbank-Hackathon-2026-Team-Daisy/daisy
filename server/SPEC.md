# 서버 개발 명세

개발할 범위와 동작을 이 문서에 먼저 적고, 구현·검증 후 PR로 공유합니다.
현재 상태(2026-10-01): #32의 V1 마이그레이션과 #19 피드백 수정 커밋을 로컬에서 통합했습니다. 아래 날짜별 기록의 마이그레이션 미포함·기동 제한은 당시 범위이며 현재 상태가 아닙니다. 서버 간 계약의 답변안과 항목별 처리 상태는 [#19 정리](docs/sh/2026-10-01-pr19-feedback.md#통합-후-피드백-처리표)를 따릅니다. 합의 전 답변안을 최종 OpenAPI로 취급하지 않습니다.
기존 팀 규칙과 컨벤션은 [AGENTS.md](AGENTS.md), 실행 방법은 [README.md](README.md)를 따릅니다. Jenkins CI/CD·AI·Terraform 실행은 인프라, 실행 규칙·추적·수신은 승환, 인증·인가·관리·공개 API·조회는 은현 담당입니다. 외부 계약의 미결과 실제 구현 범위는 구분합니다.

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
| API 문서 | springdoc-openapi 2.9.1을 사용합니다. `/v3/api-docs`, `/swagger-ui.html`을 제공합니다. 업무 API가 없으므로 경로 목록은 비어 있습니다. |
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

- 조회·관리 API 는 아직 없습니다. 인가 판정이 실제 요청 경로에 붙은 적이 없고 단위 테스트로만 확인했습니다.
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
| `connection_state` | `target.connection_state` (`unknown`·`connected`·`disconnected`) | **제공 (계약에 없는 추가)** — W-04 가 "연결 안 되는 환경은 고를 수 없어요" 를 하려면 필요합니다 |
| `checked_at` | `target.connection_checked_at` | 제공 (연결 확인이 돈 적 없으면 null) |
| `current.deployment_id` | `deployment_target.deployment_id` | 제공 |
| `current.commit` | `deployment.commit_sha` | 제공 |
| `current.deployed_at` | `deployment_target.finished_at` | 제공 |
| `current.image` | `deployment.image_refs` 평탄화 | **미제공 (null)** — 빌드 수신(A-06)이 없어 `image_refs` 가 빈 상태입니다 |
| `url` | `deployment_target.result` 의 `service_url` | **미제공 (null)** — `apply-result.json` 이 아직 인프라에 없습니다 (#17) |
| `health` | 같은 곳 | **항상 `unknown`** — 헬스 결과가 지금 apply 로그에만 있습니다 (#17) |
| `health_summary` | 같은 곳 | **미제공 (null)** |
| `image_digest` | `source_version.image_refs` | **미제공 (null)** — WR-09 동일성 검증은 빌드 수신 뒤입니다 |

`current` 는 그 대상에 한 번도 배포가 끝난 적이 없으면 통째로 null 입니다. **이번 PR 시점에는 항상 null** 이고, 이유가 둘입니다.

1. 실행 서비스가 아직 없어 `deployment_target` 에 행이 생기지 않습니다.
2. **소유 경계입니다.** 설계 2장이 `deployment` 모듈(Deployment·DeploymentTarget)을 승환 소유로, `project` 모듈(Project·Target·SourceVersion)을 은현 소유로 나눴습니다. `work.md` §14 가 *"다른 담당 영역의 Repository·Entity를 직접 사용하지 않고 서비스 계약으로 연결합니다"* 로 두었으므로, `current` 를 채우려면 **deployment 모듈의 조회 서비스 계약이 필요합니다.** `target.current_deployment_target_id` 까지는 제 소유라 읽고, 그 ID 가 가리키는 행은 읽지 않습니다.

모양만 먼저 고정해 앱이 목업을 떼고 붙을 수 있게 하는 것이 이번 범위입니다.

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
| `deployed_to[]` | `deployment` 모듈 | **미제공 (null)** — 소유 경계입니다. A-02 의 `current` 와 같은 이유입니다 |

### 상태 대조 — 소비자 enum 에 `pending` 자리가 없습니다

승환 S1 이 *"나머지 상태도 기존 소비자 enum 을 대조하고, DB enum 을 API 에 그대로 노출하지 않는다"* 로 두어서 대조했습니다.

| DB (`ck_sv_status`) | 소비자 계약 (`ios/SPEC.md` §6-7) |
|---|---|
| `succeeded` | `success` |
| `running` | `running` |
| `failed` | `failed` |
| **`pending`** | **대응 값 없음** |

`pending` 은 "빌드 결과를 받았지만 아직 시작 전" 입니다. **`running` 으로 보내지 않습니다** — 시작하지 않은 것을 진행 중으로 표시하는 건 없는 사실을 만드는 일입니다. 목록에서 빼는 것도 아닙니다. 사용자는 빌드가 접수된 것을 봐야 합니다.

**그래서 `queued` 를 네 번째 값으로 내보냅니다.** 소비자 계약에 없는 값이라 웹·앱에 알려야 합니다. 받기 어렵다면 `pending` 행을 목록에 포함한 채 `pipeline.status` 만 null 로 두는 쪽으로 바꾸겠습니다.

### `image_refs` 모양 — 가정을 적어 둡니다

설계 5.5 는 `image_refs` 를 *"성공 시 확정한 service별 이미지 객체"* 로만 적고 정확한 모양을 정하지 않았습니다. 이 값을 쓰는 쪽이 저이고 채우는 쪽은 승환 수신 서비스라, **제가 가정한 모양을 적어 두고 확인을 받겠습니다.**

```jsonc
{ "<서비스명>": { "image_ref": "ghcr.io/org/app:2311c0b", "image_digest": "sha256:..." } }
```

- 서비스가 **하나**면 `image` 에 그 `image_ref`, `image_digest` 에 그 digest 를 담습니다.
- 서비스가 **둘 이상**이면 `image`·`image_digest` 를 null 로 두고 `images: [{service, image_ref, image_digest}]` 를 채웁니다. 승환 S5 의 제안 그대로입니다.
- **임의의 첫 서비스를 고르거나 digest 를 합쳐 하나로 만들지 않습니다.**
- 모양이 다르거나 해독할 수 없으면 `image`·`images` 를 **null 로 두고 오류를 내지 않습니다.** 조회가 깨지는 것보다 그 필드만 비는 게 낫습니다.

모양이 확정되면 평탄화 함수 하나만 바뀝니다.

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
- `image_refs` 의 실제 모양은 승환 빌드 수신 서비스가 채우기 시작한 뒤에 다시 봐야 합니다. 지금은 가정한 모양과 다를 때 비는 것만 확인했습니다.
