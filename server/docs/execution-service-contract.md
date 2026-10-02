# 배포 실행 서비스 연결 초안

2026-10-01 기능 개발용 내부 계약이다. PR #19 후속 수정 요청을 반영했다. 사용자 REST DTO·인프라의 최종 wire protocol을 이 문서만으로 확정하지 않는다. 기존 API 경로는 v0.3 계약을 유지한다.

## 책임

- 은현의 사용자 API는 검증된 인증 주체와 요청을 실행 서비스에 전달한다. 실행 서비스도 접근 검사를 호출한다.
- `ExecutionAccess` 경계는 프로젝트 조회·변경 권한을 검사한다. 은현 구현이 연결되지 않으면 허용하지 않는다.
- `ExecutionInputs` 경계는 해당 프로젝트의 저장소·대상·입력 스냅샷과 확인된 빌드 결과를 제공한다. 실행 계층이 관리 도메인의 Repository를 직접 사용하지 않는다.
- 배포 서비스는 접수·승인·취소·재시도·롤백과 plan/단계 결과 채택을 담당한다. 별도 사용자 컨트롤러를 만들지 않는다.
- Jenkins 명령 서비스는 불변 명령 저장·대상 연결·state 충돌 제어를 담당하고, 워커는 트랜잭션 밖에서 HTTP를 호출한다.
- 이벤트 서비스는 같은 DB 트랜잭션 안에서 이력·seq를 저장한다. SSE는 저장된 채널을 조회하며 사용자 엔드포인트는 은현이 연결한다.

## 구현할 서비스 동작

| 동작 | 고정할 정보와 결과 |
|---|---|
| create | actor·project·source_version_id·target 목록·입력·멱등 키. 선택 빌드 ID와 정렬된 대상 목록을 hash에 포함하고 배포·prepare 명령·이벤트를 원자 저장. commit·이미지는 해당 성공 빌드에서만 가져옴 |
| approve/reject | 현재 승인 대기 대상 전체·각 승인 ID가 일치해야 함. 단일 승인/거절 결정을 원자 처리하며 하나라도 stale이면 전체 409. 삭제 확인은 pending 생성 시 고정한 프로젝트 이름과 비교. 승인에만 apply 명령과 state 락 생성 |
| cancel | actor와 요청 시각 보존. 명령 전체가 미제출임이 확인되면 직접 취소. 이미 제출됐거나 불명확한 apply는 요청만 기록하고 기존 실행·락 유지. plan STOP은 인프라 확인 설정이 있을 때만 전달 |
| retry | 실패한 원본 대상만 선택. 고정 입력과 계보를 복사한 새 배포. 원본 성공 대상은 변경하지 않음 |
| rollback | 전체 성공 원본에서 선택한 target_ids만 새 배포로 복원. 선택 대상·사용자 reason을 요청 hash에 포함하고 reason은 생성 이벤트에 저장. 원본·선택 대상은 lineage 행으로 보존. 새 plan·승인 필수, 원본 실행 입력에 사유를 섞지 않음 |
| build result | project·commit·prepare 명령/run 연결을 확인한 뒤 이미지·최종 입력 hash를 한 번만 고정. `recordBuild`는 선택한 기존 성공 빌드 확인이며 신규 빌드를 저장하지 않음 |
| plan result | 실제 실행 범위의 원천 plan ID 중복 검사, 검증 script·input·digest·expiry 확인, 이전 plan/승인 결정은 보존하고 새 revision 채택 |
| stage/result | 현재 command-target과 단조 원천 순번 검사. 역순/옛 명령 사건은 이력만 보존. 종료 대상을 늦은 진행 상태로 되돌리지 않음 |
| usage/script | 인증된 실행·대상 소속과 원천 ID 검사. 같은 내용은 무변경, 다른 내용은 충돌. 늦은 사용량 수신은 상태를 바꾸지 않음 |

## DB와 외부 호출

- project → deployment → target(ID 정렬) → state identity 정렬 순서로 잠근다. 접근·입력 서비스도 같은 트랜잭션과 순서를 준수해야 한다.
- 멱등 기록·이벤트·명령은 업무 변경과 같은 트랜잭션이다. HTTP 호출은 포함하지 않는다.
- 명령 pending → dispatching을 먼저 커밋한 뒤 제출한다. 응답 유실은 unknown이며 request_id로 기존 큐/run을 확인한다. 조회에서 못 찾았다고 자동 재전송하지 않는다.
- STOP은 prepare/replan에만 허용하고 현재 작업의 상태 소유권을 가져가지 않는다. apply에는 생성하지 않으며 과거에 저장된 apply STOP도 워커에서 거절한다. 기존 실행의 최종 결과를 계속 수신한다.
- Jenkins의 queue 취소/build stop은 run 전체를 대상으로 한다. 같은 run에 선택하지 않은 비종료 대상이 남아 있으면 부분 STOP 요청은 `STATE_CONFLICT`로 거절한다. 대상별 중단을 지원하려면 인프라의 대상 단위 제어가 필요하다. 백엔드가 몰래 선택 대상을 늘려 다른 대상까지 중단하지 않는다.
- JPA 상태 변경과 JDBC 이벤트 counter 갱신이 서로 덮이지 않도록 변경 컬럼만 갱신하고, 이벤트 counter는 journal이 전담한다.

## 미합의 외부 경계

Job 이름·파라미터·콜백 주소·인증 수단·plan 기한·원천 ID 범위·request_id 조회 기능은 인프라 확인이 필요하다. 기본 실행 설정은 꺼져 있고 테스트는 가짜 서버/독립 PostgreSQL로 수행한다. 운영 인프라나 사용자 저장소에 실제 배포 명령을 보내지 않는다.

DB 기준은 #32에서 받은 정식 V1이다. 기존 테이블을 자동 생성/수정하도록 ddl-auto를 바꾸지 않으며 이 계약 수정에서는 V1·테이블·컬럼을 변경하지 않았다.

## 은현 API에서 연결할 최소 호출

아래는 현재 Java 서비스 연결 기준이며 공개 HTTP 응답 DTO를 확정하는 내용은 아니다. 모든 actor ID는 요청 본문이 아니라 인증된 principal에서 가져온다.

| 사용자 API 동작 | 호출과 주의점 |
|---|---|
| 배포 생성 | `create(new CreateRequest(actorId, projectId, sourceVersionId, targetIds, input, idempotencyKey))`. commit만으로 재빌드를 선택하지 않는다. `targetIds`는 공개 `tgt_` ID다. 현재 전략은 recreate만 지원하며 API가 다른 전략을 수용하지 않아야 한다. |
| 승인·거절 | `decide(new DecisionRequest(actorId, projectId, deploymentId, decisions, idempotencyKey))`. decisions는 `tgt_` ID → `Decision(approvalId, approved, confirmationText)` 맵이다. 공개 요청의 단일 decision·confirm_text를 API에서 각 항목에 동일하게 전달한다. 누락·추가 대상, 옛 승인, 서로 다른 pending 프로젝트 이름은 409. 승인과 거절을 섞으면 400. |
| 취소·재시도 | 각각 `cancel(ControlRequest)`·`retry(ControlRequest)`. actor/project/deployment/선택 `tgt_` 목록/멱등 키를 넘긴다. 취소 응답은 실제 실행 종료 보장이 아니다. |
| 롤백 | `rollback(new RollbackRequest(actorId, projectId, sourceDeploymentId, triggerDeploymentId, targetIds, reason, idempotencyKey))`. source는 전체 성공 원본이며 trigger는 선택 계보 정보다. reason은 비어 있지 않은 최대 1000자·비밀값 제외. 선택 대상·사유가 달라진 같은 멱등 키는 409. |
| 배포 SSE | `openDeployment(actorId, projectId, deploymentId, lastEventId, eventType)`의 emitter를 반환한다. `Last-Event-ID` 헤더 값을 그대로 전달한다. eventType=null은 전체, 생략 가능한 단일 이벤트 이름이다. 기존 4인자 호출도 유지한다. |
| 프로젝트 SSE | `openProject(actorId, projectId, lastEventId, eventType)`. 기존 3인자 호출도 유지한다. HTTP 계층에서 `text/event-stream`, `Cache-Control: no-cache`와 필요한 CORS를 적용한다. |

명령 서비스 응답은 `IdempotencyService.Response(status, body)`다. 최초 성공 시 status/body를 저장하므로 재전송에서는 당시 응답이 반환된다. 최신 상태는 조회 API로 다시 확인한다. 현재 반환 status는 생성·재시도·롤백 201, 승인·취소 202다. body는 실행용 최소 응답이며 사용자 DTO로의 변환은 API 소유자가 담당한다. `DaisyException`은 기존 전역 예외 처리기로 보낸다.

필수 연결 bean은 `ExecutionAccess`와 `ExecutionInputs`다. `capture`는 선택한 sourceVersionId가 해당 프로젝트의 성공 빌드인지, 대상 소속·실행 입력이 유효한지 검사하고 **그 빌드의 BuildInput을 필수 반환**한다. commit으로 다른 빌드를 자동 선택하지 않는다. `projectName(projectId)`는 승인 대기 생성 시 현재 프로젝트명을 제공한다. 실행 서비스가 프로젝트를 잠근 트랜잭션 안에서 호출하며 expected confirmation은 approval 행에 고정한다. 이후 이름 변경만으로 기존 문구를 덮어쓰지 않는다. `verifyFrozen`은 재시도·롤백 시 저장된 입력을 현재 접근 권한·대상과 대조한다. `recordBuild`는 선택된 동일 빌드의 확인 결과만 반환하며 늦게 온 다른 빌드로 바꾸지 않는다. 실제 비밀값 대신 자격증명 참조를 전달한다. 서비스 메서드 내부에서 호출되므로 같은 DB 트랜잭션·잠금 순서를 따르고 외부 HTTP를 실행하지 않는다.

SSE 필터는 기존 채널 seq를 재사용한다. 제외된 행도 서버 조회 cursor는 전진하고, 전송된 이벤트 ID를 다시 번호 매기지 않는다. heartbeat·resync는 필터와 관계없이 전달한다. 필터를 변경하면서 과거 다른 종류의 이벤트까지 다시 보고 싶으면 클라이언트가 스냅샷을 재조회하고 재연결 기준점을 정해야 한다.

내부 콜백에는 별도 `ExecutionCallbackAccess` 인증 bean이 필요하다. 사용자 인증과 서비스 발신 인증을 혼동하지 않는다. 연결 전에는 누락된 bean을 가짜 허용 구현으로 대체하지 않는다. 실행 가능한 테스트 대역은 `ExecutionPostgresTest.TestConfig`에 `MOCK`으로 표시되어 있으며 운영 bean으로 복사할 대상이 아니다.

## 은현 조회 API에 연결할 서비스

`DeploymentQueryService`는 내부 읽기 서비스입니다. 공개 컨트롤러·DTO·새 OpenAPI 경로는 추가하지 않았습니다. `ExecutionAccess` 구현이 없으면 403으로 거절하고, 있으면 목록이 비어도 `requireRead(actorId, projectId)`를 호출합니다. 운영 접근 정책의 404/403을 그대로 전파합니다.

### 배포 ID → 프로젝트 ID (#42 연결)

```java
String projectId = deploymentQueries.projectIdOf(principal.accountId(), deploymentId);
// 기존 /deployments/{id}/... 경로에서 이 projectId로 실행 서비스/SSE를 호출합니다.
```

- 배포 테이블에서 소속을 찾고 `ExecutionAccess.requireRead(actorId, projectId)`가 통과한 뒤 반환합니다. 없는 배포는 404, 권한 오류는 정책의 401/404/403을 그대로 전파합니다. 정책 bean이 없으면 DB 조회 전 403입니다.
- actor는 인증된 principal에서만 가져옵니다. 조회 권한은 변경 권한이 아니므로 승인·취소·재시도·롤백의 기존 `requireWrite`는 그대로 실행합니다. 조회 후 역할이 바뀌어도 이 메서드의 성공만 믿고 실행하지 않습니다.
- 공개 경로나 입력 필드를 추가하지 않으며, 다른 모듈이 배포 Repository를 직접 읽을 필요가 없습니다.

### A-02 current — 현재 포인터가 가리키는 배포

```java
var pointers = targets.stream()
    .map(t -> new DeploymentQueryService.CurrentPointer(t.id(), t.currentDeploymentTargetId()))
    .toList();
var results = deploymentQueries.currentByTarget(actorId, projectId, pointers);
var result = results.get(target.id());
// result.status() → current_status, result.deployment() → 공개 Current DTO
```

- `targets`는 은현의 관리 서비스가 해당 프로젝트에서 읽은 대상들입니다. 포인터를 사용자 요청 본문에서 받지 않습니다. 관리 목록 조회와 이 메서드 호출을 같은 읽기 트랜잭션에서 수행하고, 목록이 100개를 넘으면 배치로 나눕니다.
- **최근 성공/완료 배포를 검색해서 current로 채우지 않습니다.** 현재 포인터가 더 오래된 성공을 가리키면 그 배포를 반환합니다. 실패한 최신 배포로 기존 현재 버전을 교체하지 않습니다.
- 반환은 `Map<targetId, CurrentResult(status, deployment)>`이며 **요청한 모든 대상**을 포함합니다. `status`는 `none / confirmed / unverified`입니다. `deployment`는 confirmed일 때만 제공하며 필드는 `deploymentId`, `sourceVersionId`, `commitSha`, `images`, `deployedAt`입니다. `images`는 `ServiceImage(service, imageRef, imageDigest)` 목록이며 서비스 이름 순으로 정렬합니다. 저장 이미지 자체가 없으면 null로 두고 추정하지 않습니다.
- 포인터 NULL은 `none`입니다. 이는 **확인된 현재 참조 없음**이며 실제 배포가 전혀 없거나 인프라가 삭제됐다는 판정이 아닙니다.
- NULL이 아닌 포인터가 없거나 다른 프로젝트·대상을 가리키는 경우, 성공 상태·종료 시각이 확인되지 않는 경우, 저장 이미지 JSON 구조가 잘못된 경우는 해당 대상만 `unverified`입니다. 성공 이력만으로 현재 상태를 표현할 수 없는 상황을 성공으로 꾸미지 않습니다. 실제 상태 판정은 인프라 관측 계약으로 별도 처리합니다.
- 권한 검사 401/404/403·잘못된 요청 400·DB 장애는 그대로 전파합니다. **404/409 예외를 잡아서 대상 실패로 바꾸는 fallback을 두지 않습니다.** 권한 검사와 SQL 바깥에서, 포인터·로컬 JSON 해석 결과만 대상별로 분류합니다.
- 기존 `current()`는 호환성을 위해 유지합니다. NULL 포인터는 map에서 빠지고 소속 불일치는 404, 성공/종료/이미지 구조 부족은 409로 전체 실패하는 이전 계약입니다. #42의 A-02는 새 `currentByTarget()`으로 전환하고 일괄 실패 후 대상별 재호출을 제거해야 합니다. 새 메서드는 대상 실패로 예외를 던지지 않으므로 같은 읽기 트랜잭션 안에서도 rollback-only를 만들지 않습니다. 은현님의 `NOT_SUPPORTED` 해제·컨트롤러 연결은 해당 PR에서 검증합니다.
- API `Current.commit`에는 `commitSha`, `Current.deployed_at`에는 기록된 대상 성공 완료 시각인 `deployedAt`을 사용합니다. 실제 트래픽 전환 시각을 측정한 값은 아닙니다.
- 공개 scalar `image`·`image_digest`는 서비스가 정확히 하나일 때만 채웁니다. MSA는 대표 하나를 고르지 않습니다. A-02 서비스별 이미지 목록 추가 여부는 은현과 소비자가 공개 계약에서 결정합니다.
- **현재 포인터·연결 확인은 실행부가 기록해요 (10/2 승환 지시).** `acceptState`가 검증한 apply 성공에 한해 해당 실행의 state 락을 해제하기 전에 같은 트랜잭션으로 `target.current_deployment_target_id`, `connection_state=connected`, `connection_checked_at`, `updated_at`을 갱신해요. 활성 프로젝트·대상과 state 주소·설정 revision·자격증명 참조/버전이 실행의 고정 입력과 같아야 해요. 실패·취소·unknown·중복·늦은 콜백은 덮어쓰지 않아요. 롤백은 새 배포가 성공한 뒤 새 대상 ID를 기록해요. 은현 조회는 기존 필드를 읽으면 되며 별도 갱신 호출은 필요 없어요. 연결 확인은 성공 수신 시점의 근거이고 지속적인 헬스 상태 보장은 아니에요. 과거 성공 이력을 검색해서 소급 보정하지 않아요.

### A-06 deployed_to — 빌드별 마지막 성공 이력

```java
var byBuild = deploymentQueries.deployedTo(
    actorId, projectId, page.stream().map(SourceVersion::id).toList());
// byBuild.get(version.id())를 공개 deployed_to 목록으로 변환합니다.
```

- 정확한 `source_version_id`로 조회합니다. 같은 commit의 재빌드를 섞지 않습니다. 입력은 은현 API가 선택한 프로젝트 소속 빌드 페이지이며 최대 100개입니다.
- 반환은 `Map<sourceVersionId, List<SuccessfulDeployment>>`이고 DTO 필드는 `targetId`, `deploymentId`, `deployedAt`입니다. 조회가 완료됐으나 성공 이력이 없으면 해당 ID의 목록은 `[]`입니다. 목록 자체가 연결되지 않은 기존 null과 구분합니다. 존재 여부는 관리 서비스가 판정하며 이 메서드는 다른 프로젝트·없는 빌드에 대해 정보를 노출하지 않고 빈 목록을 반환합니다.
- **빌드·대상 조합별 마지막 성공 1건**입니다. 같은 대상의 재배포가 여러 번 있어도 중복 나열하지 않습니다. `finished_at DESC, deployment_id DESC`로 마지막 행을 고르고 반환 목록은 target ID 순서입니다. 동일 시각의 ID 정렬은 결정적 tie-break일 뿐 시간 선후를 추정하지 않습니다.
- 전체 deployment가 `partially_succeeded`여도 `deployment_target.status=succeeded`이고 종료 시각이 있으면 포함합니다. 실패·대기·적용 중 대상은 제외합니다.
- 이는 **과거 배포 성공 이력**이지 현재 그 버전이 서비스 중인 대상 목록이 아닙니다. 이후 다른 빌드로 교체됐어도 이력은 남습니다. 전체 시도 이력은 별도 배포 이력 API의 책임입니다.

### 공통 제한·경계

빈 ID·중복 ID·100개 초과·NULL 목록은 400입니다. 빈 목록은 인가 검사 후 빈 map을 반환합니다. 반환 map/list는 수정할 수 없습니다. 조회는 배치 SQL 한 번씩, 파라미터 바인딩·readOnly 트랜잭션을 사용하고 업무 락·이벤트·명령을 생성하지 않습니다. 관리 Repository/Entity·인프라 HTTP를 직접 호출하지 않습니다. 스냅샷·자격증명·plan/state·임의 JSON 전체를 응답에 싣지 않습니다.

이번에 정한 것은 서버 내부 조회 기준입니다. 공개 필드 명명·일정은 은현 및 소비자와 확인하며, 이 문서만으로 실제 사용자 API 연결 완료를 선언하지 않습니다.

## 결과 수신 어댑터 구현 기준

### ExecutionInputs JSON 저장 형태

스냅샷 컬럼의 기준은 [DB 설계](database-design.md)의 §5.6 deployment·§5.7 deployment_target·§6 입력 스냅샷입니다. repository에는 저장소 ID·URL·브랜치·manifest 경로·자격증명 참조만, commonInput에는 비밀값 없는 입력과 `hash_format_version: 1`, target snapshot에는 name·type·설정 revision·자격증명 버전 참조를 고정합니다. 실제 비밀값을 넣지 않습니다.

`BuildInput.imageRefs`는 실행 도메인의 `{service: {image_ref, digest, commit_sha}}` 형태입니다. 각 서비스의 `commit_sha`는 선택 빌드와 같아야 합니다. digest를 제공하면 `sha256:`과 64자리 hex를 사용하며, 미확인이라 생략할 경우 `image_ref`는 해당 전체 commit 태그를 사용합니다. 조회 API의 `image_digest`는 이 저장 키 `digest`를 변환한 이름이지 DB JSON 키가 아닙니다. 불완전한 `recordBuild` 확인 결과는 `STATE_CONFLICT`로 거절합니다.

### 외부 결과 검증

이 절은 백엔드 구현·테스트용 제안이며 인프라가 이미 이 형식을 보낸다는 뜻이 아니다.

- 사용자 Bearer 권한과 Jenkins 서비스 간 발신 인증을 구분한다. 발신 인증 구현이 연결되지 않으면 거절한다. 인증을 우회하는 개발용 기본 구현은 두지 않는다.
- 인증 결과의 instance·허용 Job과 저장한 명령을 대조한다. payload의 `source` 문자열을 믿지 않고 검증한 instance·Job·실제 build 번호로 원천 범위를 만든다.
- request ID는 저장한 명령과 같아야 한다. 이미 연결한 queue/build 번호는 다른 값으로 교체할 수 없다. 제출 HTTP 응답보다 콜백이 먼저 도착할 수 있으므로 최초 연결과 재전송을 구분한다.
- 프로젝트·배포·대상 소속은 DB에서 확인한다. STOP은 원본 실행의 상태 콜백을 대신할 수 없다. 스크립트·AI 사용량은 상태 진행 순번과 별개로 수신한다.
- 본문 크기와 필드를 제한한다. 로그는 인프라가 먼저 비밀값을 제거한 구조화된 텍스트만 받고, 백엔드도 길이·금지 패턴을 검사한다. 정규식만으로 모든 비밀값을 탐지한다고 주장하지 않는다.
- 반복 단계는 `stage_occurrence_id`로 구분한다. 동일 occurrence의 시작·완료로 시간을 계산하고, 시작이 없으면 소요 시간을 0으로 만들지 않는다. 사건 시각만으로 최신 상태를 판단하지 않는다.
- 상태 변경과 수신 기록은 같은 트랜잭션이다. ACK는 커밋 후 반환한다. 같은 원천 ID·내용은 성공 재응답, 같은 ID의 다른 내용은 충돌이다.
- 공개 사용자 REST 경로·응답은 변경하지 않는다. 내부 수신 경로는 기본 비활성으로 두고 최종 인증·주소·payload를 인프라·은현과 맞춘 뒤 활성화한다.
