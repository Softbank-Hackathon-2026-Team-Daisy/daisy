# Daisy 서버 개발 환경

개발 범위와 검증 결과는 [SPEC.md](SPEC.md), 담당 경계와 컨벤션은 [AGENTS.md](AGENTS.md)를 참고해요.

Java 21, Spring Boot 3.5.16, Gradle 8.14, PostgreSQL, JPA/Flyway, Spring MVC, springdoc-openapi를 사용해요.

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
