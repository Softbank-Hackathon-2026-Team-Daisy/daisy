# #38 인증·조회와 실행 기능 통합 (2026-10-01)

## 보존과 병합

- 사용자 요청으로 `server/feat-deployment-execution`에서 최신 main `1ab2365`를 병합했습니다. #38 인증·인가·조회 43개 파일이 추가/수정됐으며, 충돌 없이 `930667f`로 커밋했습니다.
- 기존 실행 HEAD `a718aa0`는 `server/chore-backup-before-auth-merge`에도 보존했습니다. 배포·Jenkins·이벤트·멱등 패키지는 이 병합에서 변경되지 않았습니다. `references/`는 건드리지 않았습니다.
- 팀원 구현의 JWT 서명·발급자 검증, DB 역할·활성 상태 재조회, BCrypt를 확인했습니다. Spring Security 전체 필터 체인을 사용하지 않는다는 사실만으로 인증이 없는 것은 아닙니다. 현재 자체 Bearer 필터가 보호 경로를 검사합니다. 보안 전수 감사 완료를 의미하지 않습니다.

## 사용자 승인 후 최소 보완

1. #36 피드백: `recordBuild` 확인 결과의 commit·이미지가 NULL이면 NPE 대신 `STATE_CONFLICT`. 회귀 테스트 추가.
2. 실행 이미지 저장 키 `digest`와 조회 구현의 `image_digest` 가정 차이 수정. 공개 응답 이름은 유지하고, 실행 도메인에서 수용한 JSON을 조회에 연결하는 테스트 추가.
3. 허용 origin의 미인증 요청에서 401에 CORS 헤더가 없는 것을 실제 HTTP로 재현. MVC 설정을 인증 필터 이전의 표준 `CorsFilter` 등록으로 옮겼습니다. 기존 origin·헤더·쿠키 불허 정책 유지. 401·preflight·미허용 origin 회귀 테스트 추가.
4. 실제 `/v3/api-docs`에 Bearer scheme·보호 경로 security가 없음을 확인. 기존 인증 설정/컨트롤러에 OpenAPI annotation만 추가. 로그인은 공개이며 프로젝트 조회·내 정보는 Bearer 요구로 표시합니다.
5. ExecutionInputs JSON 형태와 DB 설계 참조를 계약 문서에 보강했습니다. 어댑터나 신규 API는 만들지 않았습니다.

## 검증

- 병합 직후 `check build --rerun-tasks --no-daemon --offline`: 121 tests, 0 skipped/failures/errors.
- 보완 후 Java 21·PostgreSQL 17.11에서 `spotlessApply check build --rerun-tasks --no-daemon --offline`: **125 tests, 0 skipped/failures/errors**, 정식 Flyway V1을 사용하는 실DB 테스트 14개 포함.
- 별도 빈 `daisy_auth_merge_1001` DB, 루프백 18089에서 jar 기동: V1 적용·JPA validate·health UP. 시험용 자격증명만 사용했고 토큰을 출력/저장하지 않았습니다.
- owner/viewer 로그인·내 정보·조회 200, 미인증/변조 토큰 401, 없는 프로젝트 404 확인. 보완 후 401의 `Access-Control-Allow-Origin`과 OpenAPI Bearer scheme·보호 경로 요구·공개 로그인도 실제 HTTP로 재확인했습니다.
- 새 Spring Security 프레임워크·의존성 추가, V1 변경, 실제 Jenkins·클라우드 실행은 없습니다. 실제 사용자 배포 API 인가·프록시 SSE·Jenkins E2E는 후속입니다.

## 확인할 PR·이슈

- **#36 은현 답변 필요:** 포트 계약 수용, 어댑터 2개 후속 연결. 승인 items를 Map으로 변환하는 방향은 맞지만 제안 예시의 `decision: approved`는 웹·앱 기존 요청 `approve/reject`와 다릅니다. 공개 요청 값을 유지하고 내부 boolean/저장 상태로 변환하도록 확인해야 합니다. 아직 댓글은 게시하지 않았습니다.
- **#38 조회 후속:** `current`·`deployed_to`는 실행 조회 서비스 연결 대기입니다. 현재 `current=null`이 항상 배포 부재를 뜻한다고 간주해서는 안 됩니다. `image_refs` 보완도 팀원에게 공유해야 합니다.
- **#35:** 확인 시점 댓글 없음. Jenkins 식별·결과·승인·state·중단 계약은 계속 대기입니다.
- **#13:** 새 댓글은 없지만 선택 필드 제공/후순위/미제공 표의 공동 답변은 남아 있습니다. #38로 제공된 조회 항목을 반영하면 됩니다.
- **#33/#30:** 기존 역할 피드백 답변 완료. #33은 아직 열려 있습니다. #37/#39는 이름·공통 문서·앱 대응 변경이며 새 서버 기능 요청은 확인되지 않았습니다. #39는 queued 수용과 Unibloom 이름/도메인 결정을 기록합니다.

## 회의록 업데이트 권고

`#19/#32 미완료`, `인증·업무 API·SSE·Jenkins 호출 모두 미착수`는 최신 상태와 다릅니다. #19/#32/#38 머지 완료, #36 실행 서비스·SSE 기반 구현/리뷰 중, 공개 배포 API 어댑터·실제 Jenkins 연결/E2E는 남음으로 구분합니다. 이름은 #37/#39의 Unibloom 결정을 확인해 반영합니다. AI 생성·수정은 인프라, 서버 실행 규칙·수신은 승환, 인증·공개 API·조회는 은현입니다. manifest 파서의 서버 잔여 범위는 별도 확인이 필요합니다.

이 기록은 로컬 통합 결과입니다. 원격 push·댓글 게시·PR 승인/머지는 수행하지 않았습니다.
