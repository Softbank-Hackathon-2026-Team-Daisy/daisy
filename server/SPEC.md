# 서버 개발 명세

개발할 범위와 동작을 이 문서에 먼저 적고, 구현·검증 후 PR로 공유합니다.
담당 경계와 컨벤션은 [AGENTS.md](AGENTS.md), 실행 방법은 [README.md](README.md)를 따릅니다.

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

업무 패키지, DB 마이그레이션, 상태 기계·큐·SSE, Terraform CLI 실행부와 AI 기능은 별도 기능 명세·구현으로 추가합니다. `TerraformRunner`, `recordAttempt(...)`, `PlanSummary`의 구체적인 호출 계약은 두 서버 담당자가 구현 전에 맞춥니다.

### 검증 결과 (2026-09-29)

- Gradle Wrapper로 `spotlessApply check build --no-daemon` 성공.
- 로컬 PostgreSQL 17 연결, Flyway 초기화와 Spring Boot 기동 확인.
- `/actuator/health`에서 `{"status":"UP"}`, `/v3/api-docs`에서 OpenAPI 응답 확인.
- 테스트 소스와 업무 마이그레이션은 아직 없습니다. 테스트 태스크 결과는 `NO-SOURCE`입니다.
- Docker Compose 구성은 작성했으며, 현재 개발 머신에 Compose 실행 환경이 없어 실제 실행 검증은 하지 못했습니다. 기존 로컬 PostgreSQL 연결 경로는 검증했습니다.
