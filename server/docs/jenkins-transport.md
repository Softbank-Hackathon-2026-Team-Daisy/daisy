# Jenkins HTTP 연결 제안

이 문서는 백엔드 transport의 **제안**이다. 인프라 담당자의 확인 전에는 실제 Job 실행에 연결하지 않는다. 현재 인프라 `cd/Jenkinsfile`의 `DEPLOY_AWS/GCP`, `IMAGE_TAG`, `IMAGE_REPO`, `APP`, `APP_REPO` 및 Jenkins 내부 승인, `ci/Jenkinsfile`의 `TRIGGER_CD`는 아래 제안과 다르다. 이 transport는 해당 파이프라인과 이미 호환된다는 뜻이 아니다. Terraform·AI 구현은 인프라가 소유한다.

`daisy.jenkins.enabled` 기본값은 false다. 활성화 시 `base-url`(context 포함), `user`, `token`(API token), `jobs`(허용 Job 전체 이름, 쉼표 구분)를 모두 공급한다. 예: `DAISY_JENKINS_BASE_URL=https://jenkins.example.invalid/jenkins/`, `DAISY_JENKINS_JOBS=daisy/prepare,daisy/apply`. 비밀값은 환경변수로만 공급한다. `connect-timeout-ms` 기본 3000, `read-timeout-ms` 기본 15000, `max-response-bytes` 기본 262144(최대 1048576)이다. transport 자체는 기동 시 호출하거나 주기적으로 실행하지 않는다. 자동 요청 전달에는 아래 워커 활성화도 필요하다.

제안 adapter는 `POST /job/{folder}/job/{job}/buildWithParameters`에 form string parameter `request_id`와 `payload`(JSON)를 보낸다. JSON에도 동일 `request_id`를 넣는다. prepare/replan/apply/stop별 Job 또는 재개 방식, payload schema, 정확한 승인 plan digest/input hash 검사, 구조화된 대상 결과·callback은 인프라와 확인해야 한다. API token Basic 인증을 사용한다([공식 인증 안내](https://www.jenkins.io/doc/book/system-administration/authenticating-scripted-clients/), [공식 Remote API](https://www.jenkins.io/doc/book/using/remote-access-api/)).

201 응답의 Location은 설정 origin/context의 정확한 `/queue/item/{positive-id}/`만 수용한다. redirects는 따르지 않는다. 이후 queue item JSON, 허용 Job의 build JSON, `POST queue/cancelItem?id=...`, `POST {build}/stop`, `{build}/logText/progressiveText?start=...`를 조회한다. callback·executable URL을 HTTP 목적지로 사용하지 않는다. 실제 Jenkins 버전·권한·API token CSRF 동작·queue/stop/progressive headers는 인프라 연결 검증에서 확인해야 한다.

request_id 복구는 queue와 최근 최대 100 build의 parameter 관측이다. 일치 1건 FOUND, 여러 queue/run AMBIGUOUS, 미발견 UNKNOWN이다. 보관 기한·조회 제한 때문에 미발견은 미실행 증거가 아니다. timeout/5xx/응답 크기 초과/잘못된 Location도 실행 여부 UNKNOWN이며 자동 재제출하지 않는다. 401/403/404는 해당 HTTP 요청 거부 분류일 뿐 과거 요청의 미실행 증거가 아니다. Jenkins 멱등 실행·정확히 한 번을 보장하지 않는다.

build `result=SUCCESS`와 stop/cancel ACK는 배포 성공·실제 종료를 뜻하지 않는다. 실제 target 결과와 사용 이미지/승인 plan 대조·실행 종료 확인은 실행 서비스가 담당한다. progressive log transport는 byte[]와 Jenkins `X-Text-Size` byte cursor를 반환한다. byte cursor를 Java 문자열 길이로 계산하지 않는다. 응답은 전부 bounded body이며 원문·credentials를 예외/로그로 출력하지 않는다.

구조화 로그 콜백과 progressive console 수집 코드를 작성했다. console은 별도 활성화가 필요하며, 단일 run 소유자·부분 UTF-8/줄 처리·이벤트와 cursor의 원자 저장 규칙은 [console 계약](jenkins-console.md)을 따른다. 인프라의 UTF-8·비밀값 제거 출력 계약 확인 전에는 활성화하지 않는다. 현재 테스트 소스 작성 단계이며 실제 Jenkins 연결 검증은 완료하지 않았다.

## 명령 워커

`daisy.jenkins.worker-enabled=true`와 transport 활성화가 모두 필요하다. `instance-id`와 `operation-jobs.prepare/replan/apply`는 인프라 확인 후 설정한다. 기본 Job 이름은 `daisy/{operation}`이라는 제안이며 실제 존재하는 Job으로 간주하지 않는다. STOP은 새 배포 Job을 만들지 않고 원본 queue/build의 제어 API를 호출한다.

명령은 DB에 먼저 저장하며, SKIP LOCKED로 가져와 `dispatching`을 커밋한 다음 HTTP를 호출한다. 시작 시 미완료 `dispatching`을 `unknown`으로 복구하여 request_id 조회를 수행한다. **현재는 백엔드 워커 한 인스턴스 전제**이며, 여러 인스턴스에서 이 시작 복구를 실행하려면 워커 소유권·lease부터 추가해야 한다.

HTTP 제출 거부가 확실한 명령만 실행 서비스에 거부 결과를 전달한다. 이 후속 처리가 실패해도 거부 기록과 다음 확인 시각이 DB에 남아 재처리한다. Jenkins queue가 build 번호 없이 취소됐다고 확인되면 남은 대상의 취소·락 해제를 별도 트랜잭션에서 처리하며, 처리 전까지 DB 재확인 대상으로 남긴다. 응답 유실은 거부와 구별하며 자동 재제출하지 않는다. 구조화된 대상 결과가 누락됐을 때 Jenkins build SUCCESS만으로 대상 성공을 만들어내지 않는다.

로컬 HTTP 대역 테스트 소스만 작성했다. 사용자 요청에 따라 이 단계에서 테스트·Gradle·formatter·실제 Jenkins 호출은 실행하지 않았다.
