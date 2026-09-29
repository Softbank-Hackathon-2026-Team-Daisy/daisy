# AGENTS.md — server/ (배포 서비스 API · AI · 검증)

담당: 하은현 (`gkdmsgus`), 김승환 (`7SH7`). 상태: v1 (2026-09-29).

루트 `AGENTS.md` 를 먼저 따라요. 이 파일은 `server/` 에만 해당하는 규칙을 더하고, 루트 하드 규칙(§4)을 느슨하게 하지 않아요.
§10 결정 기록은 두 담당자가 합의한 내용이에요. 아직 안 정한 것은 §11 에 모아 뒀어요.

## 1. 이 폴더가 하는 일

| 누가 | 무엇 |
|---|---|
| **하은현** | API 서버, GitHub Actions webhook 수신, 배포 상태 기계·승인·이력, `terraform apply` 실행, SSE, 환경별 락 |
| **김승환** | `deploy.yaml` 파싱·검증, 환경별 Terraform 생성(N-02), 검증·수정 루프(N-05), 스크립트 재사용(N-08), AI 비용 기록(N-09), 공통 Terraform CLI 실행부 |

## 2. 기술 스택

| 항목 | 값 | 왜 |
|---|---|---|
| 언어 | **Java 21 (LTS)** | Gradle 8.14 가 JDK 25 미지원(9.1+ 필요) |
| 프레임워크 | **Spring Boot 3.5.16** | 3.5 계열 마지막 패치 |
| 빌드 | **Gradle 8.14 (Kotlin DSL), 단일 모듈** | 이틀짜리에서 모듈 경계를 잘못 그으면 되돌리기 비쌈 |
| DB | **PostgreSQL 17 + JPA + Flyway** | |
| API 문서 | **springdoc-openapi 2.9.1** | Boot 3.5.16 기준으로 빌드된 판 (2.8.17 은 3.5.13 기준) |
| 작업 큐 | **Postgres 작업 테이블 (`FOR UPDATE SKIP LOCKED`)** | 3장 참고 |
| 진행 전달 | **SSE (`SseEmitter`)** + `deployment_log.seq` 로 재연결 | |
| IaC 실행 | **Terraform CLI 프로세스 호출** | ADR-003 |
| 포맷 | **Spotless + google-java-format** | 정적 분석은 예선 동안 이것만 |

## 3. 폴더 구조와 경계

```
server/
├─ manifest/   deploy.yaml 파싱·검증                    ← 김승환
├─ ai/         Terraform 생성 · 검증·수정 루프 · 비용 기록 ← 김승환
├─ job/        배포 상태 기계 · 워커 · 환경별 락          ← 하은현
├─ history/    배포 이력 · 로그 · 롤백                   ← 하은현
├─ target/     대상 환경 등록 · 자격증명 참조             ← 하은현
├─ api/        컨트롤러 · DTO · SSE · 전역 예외           ← 하은현
└─ common/     ID 생성 · 시간 · 공통 응답                 ← 공용
```

- `controller/` `service/` `repository/` 로 **최상위를 나누지 않아요.** 기능 폴더 안에서 나눠요
- **폴더끼리는 서비스 메서드로만** 불러요. 남의 폴더 Repository·Entity 를 직접 쓰지 않아요
- 공통 Terraform CLI 실행부는 **김승환 소유**. 하은현은 호출만 해요

| 공통 실행부 (김승환) | server (하은현) |
|---|---|
| 프로세스 실행 · 출력 전달 · 타임아웃 · 중단 요청 | 상태 · 로그 저장 · SSE · 락 |

### 파트 사이 호출 지점

| 방향 | 무엇 |
|---|---|
| ai → job | `recordAttempt(deploymentId, target, attempt, errorSummary)` — 호출되면 **하은현이 `step.failed` + `attempt` 를 SSE 로 발행**해요. 김승환 쪽에서 따로 이벤트를 보내지 않아요 |
| ai → job | 검증 끝난 **tfplan 경로**와 `PlanSummary` 전달 |
| job → ai | **stale 감지 시 재 plan 요청.** 기존 Terraform 코드로 재 plan → 위험 검사 → 새 결과로 재승인. **단순 stale 재 plan 은 `attempt` 에 포함하지 않아요** |

## 4. 작업 큐 — Postgres

`terraform apply` 가 수 분 걸려서 요청을 붙잡을 수 없어요. 워커는 반드시 필요해요.

Redis 대신 Postgres 를 쓰는 이유는 **어차피 DB 에 다 적어야 하기 때문**이에요.

| 필요한 것 | 근거 | 어떻게 |
|---|---|---|
| 배포 로깅 (누가·언제·어떤 버전·어디에) | 공식 요구사항 | 테이블이 어차피 필요 |
| 롤백 | Q&A 평가 대상 | 배포 이력이 DB 에 있어야 함 |
| SSE 재생 (`Last-Event-ID`) | API 계약 4-5 | `deployment_log.seq` → `WHERE seq > ?` |
| 동시 배포 락 | 공식 요구사항 · N-05 | **같은 Terraform state 를 공유하는 배포 대상** 기준 유니크. 승인 접수 시점부터 잡아요 |
| 워커 | | `FOR UPDATE SKIP LOCKED` |

노션 **N-05 성공 기준이 이미 "Postgres 기반 상태 전이 / 동시 요청 2건 → 중복 배포 0건 / 재시작 후 이어서 진행"** 이에요.

> **조건**: 백엔드 인스턴스를 2대 이상 띄우기로 정해지면 그때 Redis Streams 로 올려요.

## 5. 테이블

```
deployment(id, project_id, image_tag, commit, status, strategy,
           requested_by, started_at, finished_at)

deployment_target(deployment_id, target, status, attempt, error_summary,
                  plan_path, plan_summary JSONB, ai_reused, public_url, ...)
    attempt       최초 생성 포함 총 시도 횟수 (1/3 부터 시작)
                  AI 수정 횟수만 세요. **stale 로 인한 재 plan 은 올리지 않아요**
    ai_reused     검증된 스크립트를 재사용해 AI 호출이 0회였는지 (N-08)
                  "AI 호출 0회" 수치를 여기서 뽑아요
    plan_path     {작업루트}/{deployment_id}/{target}/tfplan
                  작업루트는 레포 밖. apply 에 필요한 작업 디렉터리를 함께 유지해요
                  재 plan 하면 이전 승인을 무효화하고 새 plan 에 승인을 연결해요
                  성공·거절·취소·만료 모두 실행 종료를 확인한 뒤 정리해요
    plan_summary  김승환 PlanSummary 를 그대로 담아 API 로 내보냄

deployment_log(id, deployment_id, target, seq, level, step, message, at)
    seq           채널 안에서 단조 증가. SSE id 로도 같은 값

deployment_artifact(deployment_id, target, image_ref, revision, public_url)

target_lock(state_key UNIQUE, deployment_id, acquired_at)
    state_key  같은 Terraform state 를 공유하는 배포 대상 단위
               (한 state 에 여러 target 이 묶일 수 있어 target 기준으로는 틈이 생겨요)
               승인 접수 시점부터 잡아요

ai_usage(id, deployment_id, target, step, attempt, provider, model,
         input_tokens, output_tokens, usage_details JSONB,
         cost_usd, status, created_at)
    AI 호출 1건당 1행. 검증된 스크립트 재사용으로 호출이 없으면 행을 만들지 않아요
    status   호출 종료 후 성공·실패와 사용량을 한 번에 기록해요
             실패해서 토큰·비용을 확인하지 못하면 0 이 아니라 NULL 로 남겨요
    재사용 여부는 배포 기록에 따로 남겨 "AI 호출 0회" 수치와 연결해요
```

`id` 접두사는 API 계약 그대로: `prj_` `src_` `ir_` `tgt_` `dep_` `apv_` `pat_` `job_`

## 6. 컨벤션

- **커밋·브랜치·PR 은 `CONTRIBUTING.md` 를 따라요.** 여기서 따로 정하지 않아요
- DTO 는 `record`, 엔티티는 컨트롤러 밖으로 내보내지 않아요
- JSON 은 **`snake_case` 전역 설정** (`spring.jackson.property-naming-strategy`). 필드마다 `@JsonProperty` 를 붙이면 빠뜨려요
- 에러는 `DaisyException(ErrorCode, ...)` 만 던지고 **HTTP 변환은 `@RestControllerAdvice` 한 곳**에서. 컨트롤러에서 `try/catch` 하지 않아요
- 트랜잭션은 기본 `readOnly`. **외부 호출(terraform · LLM · 클라우드)은 트랜잭션 밖에서** 해요. 수 분 걸려서 커넥션 풀이 말라요
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
- 계약을 바꿀 때는 루트 §5-2 대로 **소비자에게 이슈로 먼저 알리고** 머지
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

- 이 폴더 밖은 건드리지 않아요. 필요하면 이슈로 (루트 §9)
- `deploy.yaml` 스키마 · API 계약 · Terraform 모듈 입력 변수는 **임의로 바꾸지 않아요**
- `terraform apply` / `destroy` / 클라우드 삭제 명령은 **사람 확인 없이 실행하지 않아요** (루트 §4-2)
- 목업은 `// MOCK:` 주석을 남겨요
- 작업 전에 아래 **결정 기록**을 읽어요

## 10. 결정 기록

| 날짜 | 결정 | 이유 | 단계 |
|---|---|---|---|
| 2026-09-29 | **Spring Boot 3.5.16** | 3.5 계열 마지막 패치. 3.5.15 에 `NimbusJwtDecoder` 의 `jws-algorithms` 보안 수정(#50118)이 있고 Bearer 인증을 쓰기로 해서 | 1 |
| 2026-09-29 | **Boot 3.5 계열 유지 (4.x 아님)** | 4.0.0 이 2025-11 릴리스라 코딩 모델 학습 데이터에 적음. `spring-boot-starter-web` → `-webmvc` 로 이름이 바뀌어 3.x 예제와 안 맞음 | 1 |
| 2026-09-29 | **Java 21 (25 아님)** | Gradle 8.14 가 JDK 25 미지원(9.1.0+ 필요). Boot 4 baseline 도 17 이라 25 가 필수 아님 | 1 |
| 2026-09-29 | **단일 모듈 + 패키지 분리** | 이틀짜리에서 모듈 경계를 잘못 그으면 옮기는 데 반나절 | 1 |
| 2026-09-29 | **작업 큐를 Postgres 로** (`FOR UPDATE SKIP LOCKED`) | 배포 로깅·롤백·SSE 재생이 어차피 DB 필요. `seq` 하나로 큐·재생·락이 한 테이블. N-05 성공 기준도 Postgres 기반. **인스턴스 2대 이상이면 Redis 로 전환** | 1 |
| 2026-09-29 | **`attempt` = 최초 생성 포함 총 시도 횟수** | AI 호출을 아끼려고. `1/3` 부터 시작하고 AI 수정은 최대 2번 | 1 |
| 2026-09-29 | **`attempt` 는 환경별 행. 한 환경이 3회 실패해도 나머지는 계속 진행** | AWS 는 IAM, GCP 는 API 활성화처럼 실패 원인이 다름. 전체로 묶으면 한쪽에서 막히는 순간 다른 쪽은 시도도 못 함 | 1 |
| 2026-09-29 | **`terraform apply` 실행은 server(하은현), 생성·검증은 ai(김승환)** | 실행이 상태 기계·락·SSE·취소와 붙어 있음. 김승환이 검증한 tfplan 경로를 넘기면 그 파일로 apply | 1 |
| 2026-09-29 | **인증은 Bearer 단일** (v0.1 의 httpOnly 쿠키안 대신) | 두 방식을 같이 받으면 필터를 두 벌 만들어야 함. 웹 `EventSource` 문제는 web 파트와 별도로 | 2 |
| 2026-09-29 | **JSON `snake_case` 전역 설정** | API 계약이 `next_cursor` 형식. 필드마다 `@JsonProperty` 를 붙이면 빠뜨림 | 1 |
| 2026-09-29 | **정적 분석은 예선 동안 Spotless 만** | 규칙 맞추다 CI 게이트에 막히면 그 시간이 기능에서 빠짐. 기간 때문이지 도구가 나빠서가 아님 | 1 |
| 2026-09-29 | **`tfplan` stale 시 재 plan → 재승인.** 단순 stale 재 plan 은 `attempt` 에 포함하지 않음 | `attempt` 는 AI 수정 횟수를 세는 값이라, 시간이 흘러서 생긴 재 plan 까지 세면 의미가 흐려짐 | 1 |
| 2026-09-29 | **락 기준은 같은 Terraform state 를 공유하는 배포 대상.** 승인 접수 시점부터 | 그 전에 이미 stale 된 plan 은 락으로 못 막아서 stale 처리를 따로 둠 | 1 |
| 2026-09-29 | **작업 디렉터리는 레포 밖.** 재 plan 시 이전 승인 무효화, 성공·거절·취소·만료 모두 실행 종료 확인 후 정리 | tfplan 만으로는 apply 가 안 되고 작업 디렉터리가 함께 필요. 승인은 특정 plan 에 묶여야 의미가 있음 | 1 |
| 2026-09-29 | **취소는 apply 전까지, 이후는 중단 요청.** 중단 요청은 즉시 종료·롤백을 보장하지 않고 실제 프로세스 종료 결과로 최종 상태를 기록 | `terraform apply` 를 중간에 죽이면 state 가 깨짐 | 1 |
| 2026-09-29 | **공통 Terraform CLI 실행부는 김승환 소유** — 프로세스 실행·출력 전달·타임아웃·중단 요청까지. 상태·로그·SSE·락은 server | 실행은 검증 루프와 붙고, 상태 관리는 상태 기계와 붙음 | 1 |
| 2026-09-29 | **AI 비용은 고정 환율 + 응답에 적용 환율과 "추정" 표기.** USD 를 배포 단위로 합산한 뒤 원화로 환산·반올림 | 실시간 환율 API 는 발표 중 실패하면 승인 화면이 안 뜸. 건별 환산 후 합산하면 반올림 오차가 쌓임 | 1 |
| 2026-09-29 | **`ai_usage.status` 추가.** 실패해서 토큰·비용을 확인 못 하면 0 이 아니라 NULL | 실패한 호출도 입력 토큰은 과금됨. 0 으로 두면 "비용 없음"과 구분이 안 됨 | 1 |

## 11. 아직 정하지 못한 것

| 무엇 | 상태 | 누가 |
|---|---|---|
| **적용 환율 숫자** | 방식은 확정(고정 상수 + 응답에 표기). **숫자만 남음** | server 둘 |
| `deploy.yaml` 스키마 | 레포 §12-5(평면)와 노션 IR(`services:` 맵)이 갈려 있음 | **팀 회의** |
| 외부 공개 방식 (HTTPS) | Cloudflare Tunnel 제안. **웹훅 수신 · iOS TestFlight 심사 · 온프레미스 데모** 세 군데가 같은 걸 기다림 | **팀 회의** |
