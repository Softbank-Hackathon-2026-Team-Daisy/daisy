# AGENTS.md — server/ (배포 요청 · 승인 · 실행 추적 · API)

담당: 하은현 (`gkdmsgus`), 김승환 (`7SH7`). 상태: 2026-10-01 Jenkins 분담 반영.

루트 `CLAUDE.md`와 `CONTRIBUTING.md`를 먼저 따라요(현재 루트 `AGENTS.md` 없음). 이 파일은 `server/`에만 해당하는 규칙을 더해요.
§10의 과거 결정 중 superseded 표시는 이후 합의로 대체된 기록이에요. 아직 안 정한 것은 §11에 모아 뒀어요. 상세 데이터 의미는 [DB 설계](docs/database-design.md), 구현 범위는 [SPEC](SPEC.md)을 봐요.

## 1. 이 폴더가 하는 일

| 누가 | 무엇 |
|---|---|
| **하은현** | 인증·인가, 프로젝트·저장소·대상·버전 관리, 공개 REST·조회·OpenAPI, 사용량 합산·원화 응답 |
| **김승환** | 배포 상태·승인·제어 규칙, state 락·멱등성·복구, Jenkins 요청·결과 수신, 로그·사용량 원본 연결, 공통 오류·SSE 기반 |
| **인프라팀** | Jenkins CI/CD, 이미지 빌드·게시, AI·Terraform 생성·검증·실행·재사용, 원본 산출물·state 운영 |

## 2. 기술 스택

| 항목 | 값 | 왜 |
|---|---|---|
| 언어 | **Java 21 (LTS)** | Gradle 8.14 가 JDK 25 미지원(9.1+ 필요) |
| 프레임워크 | **Spring Boot 3.5.16** | 3.5 계열 마지막 패치 |
| 빌드 | **Gradle 8.14 (Kotlin DSL), 단일 모듈** | 이틀짜리에서 모듈 경계를 잘못 그으면 되돌리기 비쌈 |
| DB | **PostgreSQL 17 + JPA + Flyway** | |
| API 문서 | **springdoc-openapi 2.9.1** | Boot 3.5.16 기준으로 빌드된 판 (2.8.17 은 3.5.13 기준) |
| 명령·조회 예정 | **Postgres `jenkins_execution`** | durable 제출·폴링·장애 복구 설계, 구현 완료 아님 |
| 진행 전달 | **SSE (`SseEmitter`)** + `deployment_log.seq` 로 재연결 | |
| IaC 실행 | **인프라 Jenkins의 plan/apply Job** | 서버가 Terraform CLI를 다시 구현하지 않음 |
| 포맷 | **Spotless + google-java-format** | 정적 분석은 예선 동안 이것만 |

## 3. 폴더 구조와 경계

```
src/main/java/com/teamdaisy/server/
├─ identity/             인증·인가                      ← 하은현
├─ project/              프로젝트·대상·빌드              ← 하은현
├─ deployment/           배포·대상·plan·승인             ← 김승환
├─ jenkins/              명령·수신·state 락              ← 김승환
├─ script/ · ai/          산출물·AI 사용량 원본            ← 승환 수신, 은현 조회
├─ history/ · idempotency/ 이벤트·재생·멱등성             ← 김승환
└─ common/               공통 오류·요청 추적             ← 공용
```

- `controller/` `service/` `repository/` 로 **최상위를 나누지 않아요.** 기능 폴더 안에서 나눠요
- **폴더끼리는 서비스 메서드로만** 불러요. 남의 폴더 Repository·Entity 를 직접 쓰지 않아요
- Terraform CLI·AI 실행부는 **인프라 소유**예요. 서버는 실행·조회 서비스 계약으로 연결해요

| 실행 규칙·수신 (김승환) | 공개 API·관리·조회 (하은현) |
|---|---|
| 상태·승인·명령·결과·로그·SSE·락·멱등성 | 인증·인가 서비스 제공, DTO·입력 검증·OpenAPI·조회·집계 |

### 파트 사이 호출 지점

| 방향 | 무엇 |
|---|---|
| 은현 API → 승환 실행 서비스 | 인증된 actor·프로젝트·대상·source_version/plan을 전달. 실행 서비스도 제공받은 인가 서비스를 사용 |
| 승환 → 인프라 Jenkins | `daisy-cd-plan` 준비 → 사용자 승인 → `daisy-cd-apply`. 승인된 plan만 적용 |
| 인프라 → 승환 수신 | 서버가 상태·로그·산출물을 폴링. request_id 검색·구조화된 plan/대상 결과는 추가 연동 확인 필요 |
| stale → 재plan | 이전 승인 무효화, 새 plan·재승인. **단순 stale 재plan은 attempt를 올리지 않음** |

## 4. 명령·상태·복구 — Postgres

실제 apply는 Jenkins가 실행해요. 서버는 HTTP 요청을 붙잡지 않고 저장된 명령과 실제 실행을 추적하는 작업이 필요해요.

Redis 대신 Postgres 를 쓰는 이유는 **어차피 DB 에 다 적어야 하기 때문**이에요.

| 필요한 것 | 근거 | 어떻게 |
|---|---|---|
| 배포 로깅 (누가·언제·어떤 버전·어디에) | 공식 요구사항 | 테이블이 어차피 필요 |
| 롤백 | Q&A 평가 대상 | 배포 이력이 DB 에 있어야 함 |
| SSE 재생 (`Last-Event-ID`) | API 계약 4-5 | `deployment_log.seq` → `WHERE seq > ?` |
| 동시 배포 락 | 공식 요구사항 · N-05 | **같은 Terraform state 를 공유하는 배포 대상** 기준 유니크. 승인 접수 시점부터 잡아요 |
| 제출·폴링 | | 명령 전달 상태, `next_check_at`, `log_cursor`; 외부 요청은 트랜잭션 밖 |

노션 **N-05 성공 기준이 이미 "Postgres 기반 상태 전이 / 동시 요청 2건 → 중복 배포 0건 / 재시작 후 이어서 진행"** 이에요.

> 인스턴스 수만으로 Redis를 추가하지 않아요. 기존 DB 동시성·복구 경로가 실제 요구를 충족하지 못할 때 검토해요.

## 5. 테이블

17개 테이블·전체 컬럼·FK·CHECK·부분 UNIQUE는 [DB 설계 §5](docs/database-design.md#5-전체-테이블-사전)를 단일 사전으로 사용해요. 이곳에 오래된 축약 스키마를 중복하지 않아요. JPA 매핑 초안은 생성 동작·DB 기본값 적용을 보장하지 않으며, Flyway·PostgreSQL 검증은 별도예요.

- `source_version`은 같은 commit 재빌드를 별도 ID로 보존해요. 선택한 빌드의 `source_version_id`로 배포를 연결하고 성공 `image_refs`를 덮어쓰지 않아요.
- `image_refs`는 서비스별 map을 유지해요. API의 scalar `image_digest`는 단일 서비스일 때 해당 값, MSA 대표 선택은 소비자와 협의가 필요해요.
- `kind=normal/retry/rollback`은 내부 값이에요. retry·rollback은 새 배포이며 API enum·필드에 그대로 노출한다고 가정하지 않아요.
- `attempt`는 미생성·AI 미호출에서 0, 실제 최초 생성부터 1..3이에요. 재사용 여부·AI 호출 실패와 별도로 기록하고 API의 0 표시 방식은 미결이에요.
- 승인 행은 대상의 특정 plan에 연결해요. 다중 대상 승인 ID·삭제 `confirm_text`는 은현·소비자와 확인해요.
- `ai_usage`는 실제 호출당 1행, 재사용으로 호출이 없으면 0행이에요. LLM 결과와 Terraform 검증 결과를 구분하고 미확인은 NULL이에요. Jenkins 토큰 합계로 가짜 호출 행을 만들지 않아요.
- `target_lock.state_identity`는 실제 같은 state 충돌 범위예요. unknown에서는 유지하며 실제 실행 종료·해제 근거를 기록한 뒤 소유 ID로 해제해요.

기존 API ID 접두사는 유지해요. 새 내부 ID 접두사를 소비자 계약으로 확정하지 않아요.

## 6. 컨벤션

- **커밋·브랜치·PR 은 `CONTRIBUTING.md` 를 따라요.** 여기서 따로 정하지 않아요
- DTO 는 `record`, 엔티티는 컨트롤러 밖으로 내보내지 않아요
- JSON 은 **`snake_case` 전역 설정** (`spring.jackson.property-naming-strategy`). 필드마다 `@JsonProperty` 를 붙이면 빠뜨려요
- 에러는 `DaisyException(ErrorCode, ...)` 만 던지고 **HTTP 변환은 `@RestControllerAdvice` 한 곳**에서. 컨트롤러에서 `try/catch` 하지 않아요
- 트랜잭션은 기본 `readOnly`. **외부 호출(Jenkins · 산출물 조회)은 트랜잭션 밖에서** 해요
- 로그는 **JSON 한 줄**. `X-Request-ID` 를 받으면 그대로 쓰고 없으면 만들어서 응답 헤더로 돌려줘요 (샘플 앱도 같은 방식이라 화면 → 서버 → 배포된 앱까지 한 줄로 추적돼요)
- **비밀값·토큰·클라우드 키를 로그에 남기지 않아요.** `tfplan` 도 변수값이 들어가서 비밀값 취급해요
- 시간은 ISO 8601 UTC, 금액은 원 단위 정수
- 배포 생성·승인·롤백 `POST` 는 `Idempotency-Key` 필수

### 테스트 — 붙이는 곳만

커버리지 목표를 두지 않아요. **깨지면 데모가 죽는 곳만** 써요.

| 써요 | 안 써요 |
|---|---|
| 상태 기계 전이 (`job/`) | 컨트롤러별 MockMvc 전수 |
| `deploy.yaml` 파싱·검증 (`manifest/`) | 엔티티 getter/setter |
| 락 — **같은 `state_key`** 동시 2건 → 1건만 (**N-05 성공 기준**) | 외부 클라우드 실제 호출 |
| 멱등성 — 같은 키 2번 → 배포 1건 | |

통합 테스트는 `@SpringBootTest` + `docker compose` 의 Postgres 를 써요. Testcontainers 는 넣지 않아요.

## 7. 다른 파트와의 약속

- **OpenAPI 명세 제공** (web, ios) — springdoc 이 코드에서 생성. **단일 원천은 OpenAPI 문서**, 노션 「Backend API Endpoint」는 합의 기록·변경 알림용
- 계약을 바꿀 때는 **소비자에게 이슈로 먼저 알리고** `CONTRIBUTING.md`의 인터페이스 리뷰 규칙을 따라요
- 인증은 **Bearer 단일** (REST·SSE 둘 다). 웹 `EventSource` 가 헤더를 못 붙이는 문제는 web 파트와 별도로 풀어요
- `deploy.yaml` 스키마는 **팀 결정** — 회의 확정 후 반영

## 8. 실행 방법

```bash
docker compose up -d postgres    # Postgres 17
./gradlew bootRun                # http://localhost:8080
./gradlew spotlessApply          # 커밋 전 포맷
./gradlew check                  # spotlessCheck + test
```

설정은 `application.yml` + 프로파일 `local`/`ci`. **값은 전부 환경변수로 덮어쓸 수 있게** 둬요.
비밀값은 환경변수로만 받고 `.env` 는 커밋하지 않아요. 예시는 `.env.example` 에 가짜 값으로.

## 9. AI 에이전트에게

- 이 폴더 밖은 건드리지 않아요. 필요하면 담당자에게 제안해요
- `deploy.yaml` 스키마 · API 계약 · Terraform 모듈 입력 변수는 **임의로 바꾸지 않아요**
- `terraform apply` / `destroy` / 클라우드 삭제 명령은 **사람 확인 없이 실행하지 않아요**
- 목업은 `// MOCK:` 주석을 남겨요
- 작업 전에 아래 **결정 기록**을 읽어요

## 10. 결정 기록

| 날짜 | 결정 | 이유 | 단계 |
|---|---|---|---|
| 2026-09-29 | **Spring Boot 3.5.16** | 3.5 계열 마지막 패치. 3.5.15 에 `NimbusJwtDecoder` 의 `jws-algorithms` 보안 수정(#50118)이 있고 Bearer 인증을 쓰기로 해서 | 1 |
| 2026-09-29 | **Boot 3.5 계열 유지 (4.x 아님)** | 4.0.0 이 2025-11 릴리스라 코딩 모델 학습 데이터에 적음. `spring-boot-starter-web` → `-webmvc` 로 이름이 바뀌어 3.x 예제와 안 맞음 | 1 |
| 2026-09-29 | **Java 21 (25 아님)** | Gradle 8.14 가 JDK 25 미지원(9.1.0+ 필요). Boot 4 baseline 도 17 이라 25 가 필수 아님 | 1 |
| 2026-09-29 | **단일 모듈 + 패키지 분리** | 이틀짜리에서 모듈 경계를 잘못 그으면 옮기는 데 반나절 | 1 |
| 2026-09-29 | **작업 큐를 Postgres로** — 실행 소유·Redis 전환 조건은 superseded | 현재는 Jenkins 명령·폴링·복구 저장. 인스턴스 수만으로 Redis 전환하지 않음 | 1 |
| 2026-09-29 | **`attempt` = 최초 생성 포함 총 시도 횟수** | AI 호출을 아끼려고. `1/3` 부터 시작하고 AI 수정은 최대 2번 | 1 |
| 2026-09-29 | **`attempt` 는 환경별 행. 한 환경이 3회 실패해도 나머지는 계속 진행** | AWS 는 IAM, GCP 는 API 활성화처럼 실패 원인이 다름. 전체로 묶으면 한쪽에서 막히는 순간 다른 쪽은 시도도 못 함 | 1 |
| 2026-09-29 | **server apply·ai 생성/검증 분담 — superseded** | 9/30 이후 인프라 Jenkins가 CI/CD·AI·Terraform 전부, 서버는 요청·승인·추적·수신 | 1 |
| 2026-09-29 | **인증은 Bearer 단일** (v0.1 의 httpOnly 쿠키안 대신) | 두 방식을 같이 받으면 필터를 두 벌 만들어야 함. 웹 `EventSource` 문제는 web 파트와 별도로 | 2 |
| 2026-09-29 | **JSON `snake_case` 전역 설정** | API 계약이 `next_cursor` 형식. 필드마다 `@JsonProperty` 를 붙이면 빠뜨림 | 1 |
| 2026-09-29 | **정적 분석은 예선 동안 Spotless 만** | 규칙 맞추다 CI 게이트에 막히면 그 시간이 기능에서 빠짐. 기간 때문이지 도구가 나빠서가 아님 | 1 |
| 2026-09-29 | **`tfplan` stale 시 재 plan → 재승인.** 단순 stale 재 plan 은 `attempt` 에 포함하지 않음 | `attempt` 는 AI 수정 횟수를 세는 값이라, 시간이 흘러서 생긴 재 plan 까지 세면 의미가 흐려짐 | 1 |
| 2026-09-29 | **락 기준은 같은 Terraform state 를 공유하는 배포 대상.** 승인 접수 시점부터 | 그 전에 이미 stale 된 plan 은 락으로 못 막아서 stale 처리를 따로 둠 | 1 |
| 2026-09-29 | **작업 디렉터리는 레포 밖.** 서버 로컬 보관·정리 주체는 superseded | 현재 인프라가 원본 보관·정리, 서버는 참조·digest·승인 연결 유지. 실제 종료 확인 후 정리 원칙은 유지 | 1 |
| 2026-09-29 | **취소는 apply 전까지, 이후는 중단 요청.** 중단 요청은 즉시 종료·롤백을 보장하지 않고 실제 프로세스 종료 결과로 최종 상태를 기록 | `terraform apply` 를 중간에 죽이면 state 가 깨짐 | 1 |
| 2026-09-29 | **공통 Terraform CLI 김승환 소유 — superseded** | 인프라 소유로 변경. 승환은 실행 규칙·Jenkins 수신·SSE, 은현은 인증·관리·API·조회 | 1 |
| 2026-09-29 | **AI 비용은 고정 환율 + 응답에 적용 환율과 "추정" 표기.** USD 를 배포 단위로 합산한 뒤 원화로 환산·반올림 | 실시간 환율 API 는 발표 중 실패하면 승인 화면이 안 뜸. 건별 환산 후 합산하면 반올림 오차가 쌓임 | 1 |
| 2026-09-29 | **`ai_usage.status` 추가.** 실패해서 토큰·비용을 확인 못 하면 0 이 아니라 NULL | 실패한 호출도 입력 토큰은 과금됨. 0 으로 두면 "비용 없음"과 구분이 안 됨 | 1 |
| 2026-09-30 | **kind normal/retry/rollback·attempt 0·image_refs map** | 입력·재빌드·MSA를 보존하는 내부 ERD 표현. API 매핑은 DB와 구분 | 1 |
| 2026-10-01 | **결과는 폴링, prepare/apply 분리** | 인프라 #19·#17 답변. 5초는 제안, request_id 검색·상세 산출물은 연동 확인 대기 | 1 |

## 11. 아직 정하지 못한 것

| 무엇 | 상태 | 누가 |
|---|---|---|
| **적용 환율 숫자** | 방식은 확정(고정 상수 + 응답에 표기). **숫자만 남음** | server 둘 |
| `deploy.yaml` 스키마 | 레포 §12-5(평면)와 노션 IR(`services:` 맵)이 갈려 있음 | **팀 회의** |
| 외부 공개 방식 (HTTPS) | Cloudflare Tunnel 제안. **웹훅 수신 · iOS TestFlight 심사 · 온프레미스 데모** 세 군데가 같은 걸 기다림 | **팀 회의** |
| 다중 대상 승인·삭제 확인 | API 단일 approval_id/confirm_text와 대상별 행의 매핑, 프로젝트명 확인 요청 | 은현·승환·web/ios |
| Jenkins 안전한 제출·복구 | request_id 검색·중복 실행 방지, input hash·plan 기한·부분 대상 apply | 인프라·승환 |
| 조회 projection·선택 필드 | image_digest 대표 선택, attempt 0 표시, step·빌드/사용량 DTO | 은현·승환·web/ios |
