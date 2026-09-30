# Jenkins HTTP 연결 제안

이 문서는 백엔드 transport의 **제안**이다. 인프라 담당자의 확인 전에는 실제 Job 실행에 연결하지 않는다. 현재 인프라 `cd/Jenkinsfile`의 `DEPLOY_AWS/GCP`, `IMAGE_TAG`, `IMAGE_REPO`, `APP`, `APP_REPO` 및 Jenkins 내부 승인, `ci/Jenkinsfile`의 `TRIGGER_CD`는 아래 제안과 다르다. 이 transport는 해당 파이프라인과 이미 호환된다는 뜻이 아니다. Terraform·AI 구현은 인프라가 소유한다.

`daisy.jenkins.enabled` 기본값은 false다. 활성화 시 `base-url`(context 포함), `user`, `token`(API token), `jobs`(허용 Job 전체 이름, 쉼표 구분)를 모두 공급한다. 예: `DAISY_JENKINS_BASE_URL=https://jenkins.example.invalid/jenkins/`, `DAISY_JENKINS_JOBS=daisy/prepare,daisy/apply`. 비밀값은 환경변수로만 공급한다. `connect-timeout-ms` 기본 3000, `read-timeout-ms` 기본 15000, `max-response-bytes` 기본 262144(최대 1048576)이다. runtime 기동 시 호출하거나 주기적으로 실행하지 않는다.

제안 adapter는 `POST /job/{folder}/job/{job}/buildWithParameters`에 form string parameter `request_id`와 `payload`(JSON)를 보낸다. JSON에도 동일 `request_id`를 넣는다. prepare/replan/apply/stop별 Job 또는 재개 방식, payload schema, 정확한 승인 plan digest/input hash 검사, 구조화된 대상 결과·callback은 인프라와 확인해야 한다. API token Basic 인증을 사용한다([공식 인증 안내](https://www.jenkins.io/doc/book/system-administration/authenticating-scripted-clients/), [공식 Remote API](https://www.jenkins.io/doc/book/using/remote-access-api/)).

201 응답의 Location은 설정 origin/context의 정확한 `/queue/item/{positive-id}/`만 수용한다. redirects는 따르지 않는다. 이후 queue item JSON, 허용 Job의 build JSON, `POST queue/cancelItem?id=...`, `POST {build}/stop`, `{build}/logText/progressiveText?start=...`를 조회한다. callback·executable URL을 HTTP 목적지로 사용하지 않는다. 실제 Jenkins 버전·권한·API token CSRF 동작·queue/stop/progressive headers는 인프라 연결 검증에서 확인해야 한다.

request_id 복구는 queue와 최근 최대 100 build의 parameter 관측이다. 일치 1건 FOUND, 여러 queue/run AMBIGUOUS, 미발견 UNKNOWN이다. 보관 기한·조회 제한 때문에 미발견은 미실행 증거가 아니다. timeout/5xx/응답 크기 초과/잘못된 Location도 실행 여부 UNKNOWN이며 자동 재제출하지 않는다. 401/403/404는 해당 HTTP 요청 거부 분류일 뿐 과거 요청의 미실행 증거가 아니다. Jenkins 멱등 실행·정확히 한 번을 보장하지 않는다.

build `result=SUCCESS`와 stop/cancel ACK는 배포 성공·실제 종료를 뜻하지 않는다. 실제 target 결과와 사용 이미지/승인 plan 대조·실행 종료 확인은 실행 서비스가 담당한다. 로그는 byte[]와 Jenkins `X-Text-Size` byte cursor를 반환한다. byte cursor를 Java 문자열 길이로 계산하지 않는다. 수집기는 부분 UTF-8/줄을 다음 chunk와 합치고, 민감값 필터 후 이벤트와 cursor를 같은 DB 트랜잭션으로 저장한다. 응답은 전부 bounded body이며 원문·credentials를 예외/로그로 출력하지 않는다.

로컬 HTTP 대역 테스트 소스만 작성했다. 사용자 요청에 따라 이 단계에서 테스트·Gradle·formatter·실제 Jenkins 호출은 실행하지 않았다.
