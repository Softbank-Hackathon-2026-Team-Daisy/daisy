# Jenkins 내부 콜백 초안

2026-10-01 백엔드 구현용 **제안**이다. 현재 Jenkins 파이프라인이 이 형식을 보낸다는 뜻이 아니며, 인프라와 wire protocol·서비스 인증·주소를 합의한 뒤 활성화한다. 사용자 REST API·로그인 구현은 은현 소유 그대로다.

`POST /internal/jenkins/callbacks`, `Content-Type: application/json`. 기본 비활성: `daisy.jenkins.callbacks-enabled=true`를 설정해야 경로가 등록된다. 은현이 `ExecutionCallbackAccess` bean을 제공해야 한다. 이 포트는 요청의 서비스 자격증명/인증서를 검증하고 실제 Jenkins instance ID와 허용 Job 목록을 반환한다. 구현이 없거나 허용 Job이 없으면 403이며 본문을 읽지 않는다. 자격증명 형식·프록시 인증 헤더 신뢰·네트워크 제한은 해당 인증 구현에서 합의한다. 사용자 Bearer 로그인으로 대체하지 않는다.

본문은 Content-Length와 무관하게 최대 256 KiB다. 미등록 필드·중복 JSON 키·연속 JSON 문서·숫자/불리언 문자열 강제 변환을 거절한다. Jackson 파싱 전에 인증하고 바이트 제한을 적용한다. 내부 오류 응답은 공통 안전한 오류 형식이다. 과대 본문도 현재 `VALIDATION_FAILED`(400)로 반환한다.

## 공통 envelope

```json
{
  "execution_id": "job_01234567-89ab-cdef-0123-456789abcdef",
  "request_id": "01234567-89ab-cdef-0123-456789abcdef",
  "job_full_name": "daisy/prepare",
  "build_number": 42,
  "queue_id": 81,
  "external_event_id": "run42-target1-state1",
  "source_sequence": 1,
  "occurred_at": "2026-10-01T00:00:00Z",
  "deployment_target_id": "dt_01234567-89ab-cdef-0123-456789abcdef",
  "kind": "state",
  "payload": {
    "status": "generating",
    "attempt": 1
  }
}
```

`execution_id`·`request_id`·Job은 저장한 명령과 같아야 한다. `build_number`는 양의 정수 필수, `queue_id`는 선택 양의 정수다. 처음 인증된 콜백은 dispatching/unknown/accepted 명령에만 run을 연결하며 기존 queue/build를 덮어쓰지 않는다. 동일 run의 종료 후 재전송도 허용한다. STOP 명령은 결과의 원본 실행을 대신할 수 없다.

프로젝트·배포 ID는 본문에서 받지 않고 저장한 명령에서 찾는다. `deployment_target_id`는 공개 `tgt_` ID가 아닌 이 배포의 `dt_` 행 ID다. build에는 대상·source_sequence가 없어야 한다. log의 대상은 선택(미지정은 배포 전체 로그), 다른 kind는 대상 필수다. plan/plan_stale/state/log/stage의 source_sequence는 0 이상 필수; script/usage/build에는 없어야 한다. sequence는 원천 순서이고 DB SSE seq와 다르다. source는 인증된 instance·Job·build·대상으로 해시 생성하므로 본문에 source를 허용하지 않는다.

## kind별 payload

| kind | 필드 |
|---|---|
| build | source_version_id, commit_sha, image_refs(object) |
| plan | source_plan_id, input_hash, script_id, reused_script(boolean 필수), attempt(integer 필수), artifact_ref, digest, summary, resources(array), expires_at, artifact_expires_at(선택) |
| plan_stale | plan_id, plan_digest, input_hash, confirmed_not_applied(boolean 필수), execution_terminated(boolean 필수) |
| state | status(도메인의 소문자 상태), attempt(integer 필수), error_summary(선택), result(선택; 성공은 승인 plan/digest/input/image_refs 증거 필수) |
| script | artifact_ref, content_digest, compatibility_key(선택), metadata(선택), validated_at, artifact_expires_at(선택) |
| usage | provider, model, step(generate/fix), attempt, status, input_tokens/output_tokens/usage_details/cost_usd/cost_basis(선택) |
| log | level(debug/info/warn/error), step(선택), message(비밀값 제거한 텍스트), stream_id/offset/end_offset(선택; 셋 모두 함께) |
| stage | stage_occurrence_id, step, phase(started/completed/failed), level, message(선택) |

script/usage의 `external_event_id`가 실제 script/call의 불변 원천 ID다. 같은 실제 호출·스크립트의 재전송에서 바꾸지 않는다. 저장된 자연 키와 내용 해시로 중복/충돌을 판정하며 공개 SSE 사건을 추가하지 않는다. 알려지지 않은 usage는 NULL 유지, 재사용은 가짜 0-token 호출을 만들지 않는다. plan의 reused_script는 attempt에서 추론하지 않으며 재사용은 attempt=0·실제 AI 호출 없음이 필요하다.

plan의 summary/resources는 실행 도메인의 승인용 안전한 구조만 허용한다. plan 원문·state·자격증명을 보내지 않는다. script·plan artifact_ref는 보관 위치 참조이고 콜백에서 임의 URL을 읽지 않는다. artifact·script는 prepare/replan 범위에서만 수신한다.

로그는 인프라가 사전 제거한 비밀값 없는 텍스트만 보낸다. message는 UTF-8 16 KiB 이내, 백엔드의 금지 패턴 검사는 추가 방어이며 모든 비밀값 탐지를 보장하지 않는다. log stream은 인증된 source 안에서 이름을 붙이고 byte offset으로 중복/충돌을 확인한다. 늦은 로그도 실행 상태와 별개로 보존·전달한다.

단계는 매 반복마다 독립 stage_occurrence_id를 사용하고 같은 occurrence의 step을 바꾸지 않는다. 같은 occurrence 시작과 종료 시각이 있을 때만 duration_ms를 산출한다. 시작이 없으면 duration_ms/started_at를 생략한다. 대상의 최신 상태보다 오래된 새 단계 시작과 완료 이후 늦은 시작은 ignored_stale로 저장한다. 이미 적용된 시작에 대한 늦은 완료는 종료 상태 뒤에도 소요 시간을 기록할 수 있다. 기존 완료의 재전송에서 duration을 다시 계산하지 않는다. 단계 사건은 대상 상태를 변경하지 않는다. 실제 상태는 별도 state 결과로 전달한다.

명령 연결·결과 채택·중복 수신 기록은 같은 DB 트랜잭션이다. project → deployment → 모든 deployment_target(ID 정렬) → jenkins_execution 순서로 잠근다. 서비스 커밋 이후 `{"execution_id":"job_...","external_event_id":"...","receipt_id":"..."}`로 ACK한다. receipt_id는 내부 script/usage ID, 로그/단계 DB ID 또는 원천 사건 ID이며 공개 SSE cursor가 아니다. 같은 원천 ID의 다른 내용/연결은 409이고 원본을 보존한다.

2026-10-01 일괄 검증에서 발신 인증 미연결·과대 본문·JSON 형식·Job/대상 범위 검사와 저장된 실행 연결 테스트를 통과했다. 실제 Boot jar에서도 기본 비활성 경로는 404, 활성화 후 인증 bean이 없는 요청은 안전한 403 응답임을 확인했다. DB 상태·멱등 수신은 별도 PostgreSQL 통합 테스트로 검증했다. 전체 91개 테스트·빌드가 성공했지만, 실제 발신 인증·파이프라인·프록시와의 통합은 아직 하지 않았다.
