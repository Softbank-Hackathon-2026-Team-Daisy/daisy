# 백엔드 API 연결 점검

작성: 김승환 · 2026-10-02 · 로컬 `server/feat-target-observation`

## 결론

**등록된 공개 22개·내부 2개 API 경로의 로컬 HTTP 연결과 아래 조회·OpenAPI 보완을 검증했어요.** 원본 미제공·제외 항목과 실제 인프라 검증은 남아 있으므로 전체 기능 완료는 아니에요. #13·#35는 닫지 않았고, 사용자 검사 전 push·PR도 하지 않았어요. 사용자 지시로 은현님의 기존 작성 기록을 보존하면서 승환이 서버 전체 통합 보완을 이어받았어요.

기준은 main의 #84를 합친 로컬 코드예요. 운영 서버가 이 변경을 이미 쓰고 있다는 뜻이 아니에요. 이번 검사는 직접 띄운 PostgreSQL 17의 무작위 독립 스키마와 실제 Spring Boot jar를 사용했어요. Jenkins Job 제출 경계·산출물만 **MOCK**이며 실제 Terraform·클라우드를 실행하지 않았어요.

## 발견해서 로컬에서 수정·검증한 것

| 항목 | 확인한 근거 | 처리 방향·담당 |
|---|---|---|
| Swagger 필드명이 실제 JSON과 다름 | 실제 `source_version_id`, `access_token`과 달리 스키마는 `sourceVersionId`, `accessToken`이었어요 | **로컬 수정**: 승환 공통 `OpenApiConfiguration`이 HTTP ObjectMapper를 재사용해요. 생성 스키마 필드명 HTTP 회귀 검사 통과 |
| A-02 최상위 URL·digest가 항상 null | 현재 포인터와 저장 결과가 있어도 응답에서 null로 고정했어요 | 검증된 현재 포인터의 결과를 연결했어요. 최신 성공 이력을 임의로 현재로 간주하지 않아요 |
| A-04·A-02 헬스 요약 | `health_check` 완료가 저장돼도 요약 null·health unknown으로 고정했어요 | 현재 apply 실행의 유효한 헬스 단계로 배포 시점 검사 통과/실패를 제공해요. 미관측은 unknown/null이에요. **단계 시간은 HTTP 응답 시간이나 지속적인 현재 정상의 근거가 아니에요** |
| A-04 단계별 이력 | 단계·시작 시각·시간이 저장돼도 마지막 step만 제공했어요 | `steps[{name,state,duration_ms,started_at}]`를 연결했어요. 단계별 최신 실행·발생을 선택하며 오래된 발생의 늦은 실패·ignored_stale이 최신 완료를 덮지 않는 HTTP 회귀 검사를 통과했어요 |
| OpenAPI 성공 HTTP 코드 | 실제 201/202인데 명세에는 200만 있었어요 | 명령 API 다섯 개의 실제 코드·응답 스키마를 문서화했어요. 런타임 응답은 그대로예요 |
| OpenAPI nullable 응답 | 실제 null을 스키마가 허용하지 않았어요 | 선택 필드 nullable을 반영했어요. 라이브러리가 nullable 참조를 불가능한 `type:null + $ref` 조합으로 생성하는 문제도 OAS 3.1 `anyOf` 합집합으로 보정·검증했어요 |
| 중첩 Target 스키마 충돌 | plan 대상과 배포 대상의 같은 DTO 이름이 한 스키마로 합쳐졌어요 | `PlanTarget`·`DeploymentTarget`으로 문서 이름을 분리하고 각 응답의 참조를 검증했어요 |
| 입력·오류·SSE 문서 | 필수 멱등 키·입력·오류 봉투·스트림 응답 설명이 부족했어요 | 실제 입력 규칙을 바꾸지 않고 필수 표시·공통 오류·SSE 문자열 응답과 공개 operation 설명을 보완했어요 |
| 내부 콜백 Swagger 입력 누락 | 경로는 노출되지만 HttpServletRequest로 읽어 본문·서비스 인증 정보가 없었어요 | **로컬 수정**: 승환 콜백에 Envelope 본문·X-Daisy-Jenkins-Token을 문서화해요. 실제 엄격 파싱/크기 제한은 그대로예요. CI 수신의 기존 Hidden 정책은 유지해요 |
| AI 호출 대체 ID 거절 | 인프라의 `daisy-cd-plan#18/aws/ai-1`을 기존 서버가 거절했어요 | **로컬 수정·검증**: 외부 호출 ID에만 # 허용. 중복·충돌·실패 호출도 HTTP로 확인했어요 |

관련 코드: `project/web/TargetStatusResponse.java`, `DeploymentDetailResponse.java`, `DeploymentCommandController.java`, `DeploymentRequestController.java`, `history/application/JenkinsReceiptService.java`, `infra/jenkins/daisy_server.py`의 `stage`·`applied`.

## 없는 원본·합의된 미제공은 따로 봐요

| 항목 | 현재 상태 |
|---|---|
| 회원가입 | **없어요.** 인증은 `POST /auth/token`, `GET /auth/me` 두 개예요. 환경 설정으로 생성한 데모 계정 사용이며 회원가입은 기존 범위가 아니에요 |
| 새 저장소 연결 | 저장소 이름·URL 형식 검증과 프로젝트/멤버 DB 등록이에요. 실제 GitHub 존재/권한 확인·deploy.yaml 조회·Jenkins CI 설정을 자동으로 하지 않아요. 새 프로젝트의 대상 목록은 빈 배열임을 확인했어요. 사전 설정한 데모 프로젝트의 배포 성공과 임의 저장소 자동 연결 완료는 달라요 |
| manifest raw/ref | 서버 수신·조회 경로 미구현. 프로젝트 생성 응답의 manifest는 null이에요 |
| Terraform 파일 코드 조회 WR-07 | 서버가 가진 것은 script 참조·digest·검증 정보이며 파일 본문 조회는 미제공이에요. WR-10 목록 제공과 구분해요 |
| plan 원문 | counts·risks·리소스 목록은 제공, plan_text는 원본 미보관으로 null이에요. 민감한 tfplan을 대신 내보내면 안 돼요 |
| target.reuse | 조회는 reuse_assessment를 읽지만 이 값을 계산·갱신하는 생산자가 없어요. 과거 ai_reused를 미래 재사용 가능 여부로 바꿔 쓸 수 없어요 |
| 다중 서비스 대표 URL·digest | 대표 선택 계약이 없어 scalar null이 될 수 있어요. 단일 서비스 데이터의 매핑 누락과 구분해요 |
| 환율·원화 비용 | 고정 환율 설정이 없으면 원화 null. 확인하지 못한 호출 비용도 null이에요. 임의 환율·0원으로 채우지 않아요 |
| WR-04 환경 프로필 | #84의 데모 대상 세 개에는 제공해요. 새 대상까지 자동으로 인프라를 탐색하는 기능은 아니에요 |
| 선택 필드 | commit_message·버전 표시·CI steps·script note/base_commit/input/ai_tokens/storage·프로젝트 registry/webhook_last_at 등은 #13에 미제공으로 안내됐어요 |
| 연결 테스트·리소스 조회 | A-10·A-11은 #13에서 이번 범위 제외, 버튼 비활성 안내된 항목이에요 |

## HTTP 확인표

| 경로 | 실제 검사 |
|---|---|
| POST /auth/token, GET /auth/me | 계정 로그인·내 정보, 잘못된 비밀번호 401 |
| GET·POST /projects, GET·DELETE /projects/{id} | 목록·상세·등록 201·중복 409·연결 해제 204·해제 후 404·진행 중 해제 409·viewer 쓰기 403 |
| GET /projects/{id}/targets, /targets/status | 환경 프로필·연결 ok·현재 포인터 confirmed·최상위/중첩 digest·URL·배포 시점 헬스 요약 |
| GET /projects/{id}/builds | 내부 CI 콜백으로 저장한 빌드가 목록에 나오는지 |
| POST /internal/jenkins/builds | 서비스 토큰 401·출처 불일치 403·정상 저장·중복 changed=false |
| POST /projects/{id}/deployments | 성공 빌드로 201·같은 멱등 키 같은 응답·viewer 403·잘못된 camelCase 입력 400 |
| GET /deployments/{id}, GET /projects/{id}/deployments | 승인 ID·성공 결과·URL·digest·헬스 요약·단계 시작/시간·상태 필터. 늦은 과거 실패·종료 후 stale 사건에도 최신 단계 완료 유지. 회원 아닌 프로젝트 404, 무인증 401 |
| POST /internal/jenkins/callbacks | 상태·script·plan·usage·stage·log 수신. 사용량 중복·상충 409·실패 호출 미확인 유지·성공 중복에 관측 시각 불변·락 해제 |
| POST /deployments/{id}/approvals | 대기 승인 목록 그대로 승인 202·같은 키 재전송에 apply 명령 한 건·viewer 403 |
| GET /deployments/{id}/plan | 요약과 호출 합계, detail=resources 배열·리소스, 잘못된 detail 400. OpenAPI는 두 응답을 oneOf로 표현함을 확인 |
| GET /deployments/{id}/logs | 단계/로그 수신 후 대상별 로그 조회 |
| GET /projects/{id}/scripts, /ai-usage | 수신된 스크립트와 호출별 사용량, 성공 토큰 합계·실패 null·미확인 호출 합계 |
| POST /deployments/{id}/rollback, /cancel, /retry | 성공 원본에서 새 롤백 201→미제출 취소 202, 실패 원본에서 새 재시도 201→취소. 최종 락 0개 |
| GET /deployments/{id}/events, GET /projects/{id}/events | Last-Event-ID=0 재생에 양수 id, text/event-stream·no-cache, 무인증 401 |
| /v3/api-docs, /swagger-ui.html | 명세·UI HTML/JS 200. Safari에서 실제 Swagger UI와 경로 목록 렌더링 확인. API 호출은 수동 클릭 대신 재현 가능한 HTTP 스크립트로 수행 |

`scripts/verify-result-flow.py`가 OpenAPI 경로 목록과 성공 호출 목록을 대조해 누락 경로가 있으면 실패해요. **전 경로 호출은 모든 입력 조합·장애 시나리오의 완전 검증을 뜻하지 않아요.** 기존 실제 PostgreSQL 통합 테스트와 함께 봐야 해요.

## 재실행

```sh
# JAVA_HOME, DAISY_TEST_DB_URL/USER/PASSWORD, PSQL을 로컬 테스트 환경으로 설정해요.
./gradlew spotlessApply check build --no-daemon --offline
python3 scripts/verify-result-flow.py build/libs/daisy-server-0.0.1-SNAPSHOT.jar
# --inspect를 붙이면 마지막에 Enter를 누를 때까지 Swagger UI 확인용 서버를 유지해요.
```

이번 실행은 테스트 241개 실패·오류·건너뜀 0개, HTTP 24개 경로 연결 통과예요. 종료 때 생성한 무작위 스키마의 테스트 테이블·행만 삭제하고 검증 서버를 종료해요. 실제 인프라 재배포·운영 데이터 소급 보정·회원가입은 실행하지 않았어요.

## #13·#35 처리 판단과 전달 초안

- **#13 유지:** 원래 목적은 모든 선택 기능 구현이 아니라 항목별 제공 여부 확정이에요. 조회·OpenAPI 보완은 로컬 검증됐지만, 사용자 검사·소비자 안내·머지 전이에요. 추가 제공/미제공 범위를 안내하고 반영을 확인한 뒤 닫을 수 있어요.
- **#35 유지:** 주요 실행 연결은 구현됐지만 외부 AI 호출 ID 보완은 로컬에만 있어요. 헬스 1회 HTTP 측정값은 현재 구조화 콜백에 없고, 이번 검사는 실제 Jenkins의 응답 유실·stale·state 이전 운영 검증을 대신하지 않아요. 필요한 후속을 별도 이슈로 분리하기로 합의하면 이 협의 이슈를 닫을 수 있어요.

웹·앱·백엔드에 공유할 초안(아직 게시하지 않았어요):

> 은현님 작업을 합친 뒤 서버 전체 통합 보완을 제가 이어서 진행했어요. A-02 현재 url/image_digest와 A-02·A-04 배포 시점 헬스 요약을 연결했고, A-04 targets[].steps에 name/state/duration_ms/started_at을 추가했어요. 단계 시간은 HTTP 응답 시간이 아니고, 헬스도 배포 당시 검사 결과예요. OpenAPI는 실제 snake_case·201/202·nullable·필수 입력에 맞췄어요. 공개 22개·내부 2개 경로를 격리 PostgreSQL과 실제 서버 jar로 호출했고 Jenkins는 MOCK이에요. manifest/코드/plan 원문과 미수신 헬스 HTTP 원본 등은 아직 제공하지 않아요. 현재 로컬 검증 단계이며 검토 후 PR로 공유할게요.
