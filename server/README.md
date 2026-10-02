# Unibloom 서버 개발 환경

개발 범위와 검증 결과는 [SPEC.md](SPEC.md), 담당 경계와 컨벤션은 [AGENTS.md](AGENTS.md)를 참고해요.

Java 21, Spring Boot 3.5.16, Gradle 8.14, PostgreSQL, JPA/Flyway, Spring MVC, springdoc-openapi를 사용해요.

> 인증·관리/조회·배포 실행·Jenkins 연결·이벤트/SSE와 Flyway V1이 포함돼 있어요. 현재 검증 범위와 미제공 항목은 [API 점검 결과](docs/sh/2026-10-02-backend-api-audit.md)를 봐주세요. DB 없이도 단위 테스트·컴파일은 가능하지만 DB 테스트는 아래 환경변수가 없으면 건너뛰어요.

기동 전에 `DAISY_AUTH_SECRET`(32바이트 이상 서명 키)을 비밀 환경변수로 주입해요. 데모 로그인이 필요하면 `DAISY_DEMO_OWNER_PASSWORD`·`DAISY_DEMO_VIEWER_PASSWORD`도 설정해요. 기본 사용자명은 `daisy`·`judge`이며 비밀번호 기본값은 없어요. 키·비밀번호를 문서나 Git에 적지 않아요.

PostgreSQL이 이미 설치되어 있다면 `server/`에서 아래처럼 실행해요. `createdb`는 처음 한 번만 필요해요. 로컬 계정에 암호가 없다면 빈 문자열을 지정할 수 있어요.

```bash
brew services start postgresql@17
export DAISY_DB_USER="$(id -un)"
createdb -h 127.0.0.1 -U "$DAISY_DB_USER" daisy
export DAISY_DB_PASSWORD='<로컬 PostgreSQL 암호>'
./gradlew bootRun
```

Docker Compose가 설치된 환경에서는 프로젝트용 PostgreSQL을 따로 띄울 수도 있어요.

```bash
export DAISY_DB_PASSWORD='<로컬 DB 암호>'
docker compose up -d
./gradlew bootRun
```

기본 연결은 `jdbc:postgresql://localhost:5432/daisy`, 사용자명은 `daisy`예요. 기존 PostgreSQL 계정을 쓰면 `DAISY_DB_USER`를 지정하고, 다른 주소라면 `DAISY_DB_URL`도 지정해요. 암호는 환경변수로만 전달하고 커밋하지 않아요.

서버 상태는 `http://localhost:8080/actuator/health`에서 확인해요. OpenAPI는 `/v3/api-docs`, Swagger UI는 `/swagger-ui.html`이에요.

`./gradlew spotlessApply`로 Java 코드를 포맷하고, `./gradlew check`로 포맷·테스트를 확인해요. `./gradlew build`는 컴파일까지 포함해 전체 빌드를 확인합니다. `src/main/resources/db/migration`의 Flyway 마이그레이션이 먼저 적용돼요. Hibernate는 스키마를 검증하며 테이블을 자동으로 만들지 않아요.

## Swagger UI로 확인하기

1. `POST /auth/token`에 준비한 계정을 보내요. 회원가입 API는 없어요.
2. 받은 `access_token`을 상단 **Authorize → bearerAuth**에 넣어요. `Bearer ` 접두사 없이 토큰 값만 넣어요.
3. 프로젝트·빌드·대상 조회 후 배포 생성 → plan 조회 → 승인을 순서대로 확인해요. 명령 API에는 `Idempotency-Key`가 필요하며 같은 요청 재전송에 같은 키를 사용해요.
4. 승인에는 배포 상세의 `pending_approvals`를 사용해요. 삭제가 포함되면 확인 문구도 필요해요. Swagger의 예시 ID를 실제 ID처럼 보내지 않아요.

**Try it out은 실제 요청이에요.** 운영 서버에서 배포·승인·취소를 임의로 누르지 않아요. 아래 격리 검증은 Jenkins 전송·워커를 끄고 MOCK 콜백을 사용하며, `--inspect`를 붙이면 UI를 열어볼 로컬 주소를 알려줘요. 새 저장소 등록만으로 CI·대상 설정까지 자동 완료되지는 않아요. 내부 CI 빌드 수신은 Swagger에서 숨겨져 있지만 HTTP 검사에는 포함해요.

## 실행 기능 검증과 연결

PostgreSQL 통합 테스트는 **테스트 전용 DB**와 schema 생성 권한이 필요해요. 각 테스트가 새 schema를 만들고 종료 시 자신이 만든 schema만 삭제합니다. 운영 DB를 지정하지 마세요.

```bash
export DAISY_TEST_DB_URL='jdbc:postgresql://127.0.0.1:55433/daisy_execution_test'
export DAISY_TEST_DB_USER='daisy_test'
export DAISY_TEST_DB_PASSWORD='<테스트 DB 암호>'
./gradlew spotlessApply check build --no-daemon
```

빌드 성공만 보지 말고 `build/reports/tests/test/index.html`에서 PostgreSQL 테스트가 skipped가 아닌지 확인해요. 실행부 단위 테스트의 관리·인가 포트는 명시적인 MOCK이에요. 아래 검사는 실제 로그인·인가·조회까지 연결하지만 Jenkins/Terraform은 MOCK이에요. 로컬 PostgreSQL과 `psql`, Java 21, Python 3가 필요해요.

```bash
python3 scripts/verify-result-flow.py build/libs/daisy-server-0.0.1-SNAPSHOT.jar
# UI까지 직접 보려면 끝에 --inspect를 붙여요. Enter로 종료·정리해요.
```

- 은현님 연결: [실행 서비스·인가/입력 포트·SSE 호출](docs/execution-service-contract.md).
- 인프라 연결 제안: [Jenkins 요청/복구](docs/jenkins-transport.md), [인증된 콜백](docs/jenkins-callbacks.md), [console 수집](docs/jenkins-console.md).
- `daisy.jenkins.enabled`, `worker-enabled`, `callbacks-enabled`, `console-enabled`는 기본 비활성이에요. console은 `console-sanitized-utf8-confirmed`도 필요해요. 실제 Job 계약·자격증명·발신 인증을 확인하기 전에는 켜지 않아요.
- 로컬 HTTP 검증이 실제 Jenkins·클라우드 배포 검증을 대신하지 않아요. 외부 연결에는 인프라의 주소·자격증명·Job 설정이 필요해요.
