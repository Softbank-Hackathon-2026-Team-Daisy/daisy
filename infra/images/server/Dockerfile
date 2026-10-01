# Unibloom 서버 이미지 (server/ Spring Boot). 이미지 빌드 · 게시는 인프라 담당이라 server/ 밖에 둬요 (server/AGENTS.md)
#
#   docker buildx build --platform linux/amd64 -f infra/images/server/Dockerfile -t <repo>:<커밋> server/
#
# 빌드 컨텍스트는 server/ 폴더예요. 테스트는 서버 PR의 ./gradlew check가 맡고, 여기서는 jar만 만들어요

FROM eclipse-temurin:21-jdk AS build
WORKDIR /src
COPY . .
RUN sh ./gradlew bootJar --no-daemon -q \
 && cp "$(ls build/libs/*.jar | grep -v -- '-plain.jar$' | head -1)" /app.jar

FROM eclipse-temurin:21-jre
RUN useradd --system --uid 10001 --no-create-home app
COPY --from=build /app.jar /app/app.jar
USER app
EXPOSE 8080
# 컨테이너 메모리의 75%까지 힙으로 써요 (Fargate 1GB)
ENTRYPOINT ["java", "-XX:MaxRAMPercentage=75", "-jar", "/app/app.jar"]
