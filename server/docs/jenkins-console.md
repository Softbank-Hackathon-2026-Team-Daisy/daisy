# Progressive console 수집 제안

console 수집기는 구현했으며 실제 인프라 연결 계약은 확인 전이다. 기본 설정은 꺼져 있다. 활성화에는 `daisy.jenkins.enabled`, `daisy.jenkins.console-enabled`, `daisy.jenkins.console-sanitized-utf8-confirmed`가 모두 true여야 한다. 마지막 flag는 인프라가 비밀값을 제거한 UTF-8 출력과 byte offset 계약을 확인한 뒤에만 설정한다. pattern 필터가 모든 비밀값을 찾아낸다는 보장은 없다.

현재 백엔드 한 인스턴스 전제다. 5초마다 후보 최대 8개를 조회하며 HTTP는 tick당 최대 2회다. context/origin과 허용 Job 검사는 기존 JenkinsClient를 사용한다. callback URL·현재 변경된 Job 이름을 조회하지 않는다. STOP은 console owner가 되지 않는다. 동일 instance/job/build는 advisory lock과 기존 부분 UNIQUE를 통해 소유 명령 하나만 수집하며 후속 명령은 소유자를 재사용한다. 서로 다른 deployment가 같은 run을 주장하면 수용하지 않는다.

HTTP는 트랜잭션 밖에서 한다. 저장 시 project → deployment → owner execution 순서로 잠근다. 모든 블록의 journal validation을 먼저 통과한 뒤 이벤트와 `log_cursor`를 같은 트랜잭션으로 저장한다. byte 범위와 digest가 안정적인 사건 식별자·hash를 제공한다. 재시작은 저장된 cursor에서 시작하며, 다른 commit이 cursor를 먼저 이동했다면 읽은 chunk를 버리고 다음 tick에 다시 조회한다.

`X-Text-Size - 요청 start == 반환 body byte 길이`를 요구한다. Jenkins/plugin의 offset이 원문 annotation/compression 등에 대한 다른 위치라면 해당 연결을 fail-closed하며 실제 byte mapping 계약을 먼저 맞춘다. 문자 길이로 cursor를 추정하지 않는다. `moreData=true`이면 마지막 완전한 newline까지만 소비하여 불완전 UTF-8·마지막 줄을 다음 요청에서 다시 읽는다. EOF에서는 유효한 마지막 partial line도 소비하고, 빈 최종 응답도 완료 처리한다. UTF-8 decoder는 잘못된 입력을 거절한다.

한 줄은 newline 포함 최대 16KiB다. 여러 줄은 newline 경계를 유지하면서 최대 16KiB 블록으로 묶는다. 단일 줄 초과·잘못된 UTF-8·민감값 필터 거절·offset 불일치·통신 실패는 cursor를 이동하거나 내용을 버리지 않고 수집이 중단된 위치에서 재시도한다. 장문 출력이 필요하면 인프라의 줄 분할 또는 명시적인 fragment protocol이 먼저 필요하다. raw 응답·예외·비밀값을 로그에 찍지 않는다. 오류 재시도는 bounded poll이며 즉시 busy loop하지 않는다.

console은 deployment 전체에 속한다. 텍스트를 읽어 target·단계·성공 여부를 추정하지 않는다. EOF와 `log_complete`는 console 읽기 완료만 뜻하며 deployment/target 상태·state lock을 변경하지 않는다. 구조화 callback logs는 별도 source_stream을 사용해야 같은 bytes가 이중 수집되지 않는다.

2026-10-01 일괄 검증에서 UTF-8 경계·줄 경계·range·재처리·필터·EOF 단위 테스트와 실제 PostgreSQL의 소유권·커서/event/seq 원자 rollback·재전송 테스트를 통과했다. 전체 91개 테스트와 빌드가 성공했다. 실제 Jenkins 출력·offset 계약은 아직 검증하지 않았다.
