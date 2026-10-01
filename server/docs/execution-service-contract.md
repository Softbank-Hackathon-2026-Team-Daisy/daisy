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
| build result | project·commit·prepare 명령/run 연결을 확인한 뒤 이미지·최종 입력 hash를 한 번만 고정. 관리 도메인 빌드 기록은 소유 서비스 호출 |
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
