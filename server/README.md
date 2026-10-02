# Daisy 서버 개발 환경

개발 범위와 검증 결과는 [SPEC.md](SPEC.md), 담당 경계와 컨벤션은 [AGENTS.md](AGENTS.md)를 참고해요.

Java 21, Spring Boot 3.5.16, Gradle 8.14, PostgreSQL, JPA/Flyway, Spring MVC, springdoc-openapi를 사용해요.

> 현재 브랜치는 배포 실행 서비스·Jenkins 연결·이벤트/SSE 구현 단계예요. 운영 Flyway 마이그레이션은 은현님과 버전 조율 전이므로 빈 DB 기동은 `ddl-auto=validate`에서 실패해요. [실행 SQL 초안과 독립 DB 검증](docs/execution-schema.md)은 운영 마이그레이션과 구분합니다. DB 없이도 단위 테스트·컴파일은 가능하지만 DB 테스트는 아래 환경변수가 없으면 건너뛰어요.

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

서버 상태는 `http://localhost:8080/actuator/health`에서 확인해요. OpenAPI는 `/v3/api-docs`, Swagger UI는 `/swagger-ui.html`이에요. 컨트롤러가 추가되기 전에는 API 경로 목록이 비어 있어요.

`./gradlew spotlessApply`로 Java 코드를 포맷하고, `./gradlew check`로 포맷·테스트를 확인해요. `./gradlew build`는 컴파일까지 포함해 전체 빌드를 확인합니다. Flyway 마이그레이션은 향후 `src/main/resources/db/migration`에 추가해요. Hibernate는 스키마를 검증하며 테이블을 자동으로 만들지 않아요.

## 실행 기능 검증과 연결

PostgreSQL 통합 테스트는 **테스트 전용 DB**와 schema 생성 권한이 필요해요. 각 테스트가 새 schema를 만들고 종료 시 자신이 만든 schema만 삭제합니다. 운영 DB를 지정하지 마세요.

```bash
export DAISY_TEST_DB_URL='jdbc:postgresql://127.0.0.1:55433/daisy_execution_test'
export DAISY_TEST_DB_USER='daisy_test'
export DAISY_TEST_DB_PASSWORD='<테스트 DB 암호>'
./gradlew spotlessApply check build --no-daemon
```

빌드 성공만 보지 말고 `build/reports/tests/test/index.html`에서 `ExecutionPostgresTest`가 skipped가 아닌지 확인해요. 테스트의 관리·인가 포트는 명시적인 MOCK이며 실제 인증 구현을 검증한 것은 아니에요.

- 은현님 연결: [실행 서비스·인가/입력 포트·SSE 호출](docs/execution-service-contract.md).
- 인프라 연결 제안: [Jenkins 요청/복구](docs/jenkins-transport.md), [인증된 콜백](docs/jenkins-callbacks.md), [console 수집](docs/jenkins-console.md).
- `daisy.jenkins.enabled`, `worker-enabled`, `callbacks-enabled`, `console-enabled`는 기본 비활성이에요. console은 `console-sanitized-utf8-confirmed`도 필요해요. 실제 Job 계약·자격증명·발신 인증을 확인하기 전에는 켜지 않아요.
- 사용자 REST API·로그인·조회·운영 Flyway 연결은 별도 담당 작업입니다. 이 브랜치의 실행 서비스가 있다는 이유만으로 프론트에서 바로 배포할 수 있는 것은 아니에요.
