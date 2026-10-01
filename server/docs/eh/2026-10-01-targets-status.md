# 10월 1일 환경별 현재 상태 조회 (A-02)

## 작업 범위

- `GET /projects/{id}/targets/status` 로 프로젝트에 연결된 배포 대상의 현재 상태를 돌려줘요. 소비자 모델은 `ios/SPEC.md` §6-7 의 `TargetStatus` 예요.
- `Target` 엔티티에 접근자와 `create(...)` 를 붙였어요. #19 에서 매핑만 정의하고 "생성·조회 메서드는 실제 사용 사례 구현 시 추가" 로 둔 것을 이번 사용처에서 채웠어요.
- `TargetRepository` 와 응답 DTO `TargetStatusResponse` 를 추가했어요.
- 데모 대상 세 개(`onprem`·`aws`·`gcp`)를 심는 `DemoTargetSeeder` 를 추가했어요.
- 단위 테스트 4개를 추가했어요.
- 대상 생성·수정·삭제, A-10 연결 테스트, A-11 리소스 조회는 넣지 않았어요.
- 구현은 Claude Opus 5 로 했고, 검증 명령과 결과는 아래에 그대로 적었어요.

## 설계 이유

- **집계하지 않아요.** `database-design.md` 2장이 배포 전체 상태 집계를 `deployment` 모듈(승환) 소유로 뒀어요. 이 엔드포인트는 대상별 현재 값만 읽어 내보내고 상태를 계산하지 않아요.
- **`deployment` 모듈의 Repository 를 쓰지 않아요.** `work.md` §14 가 *"다른 담당 영역의 Repository·Entity를 직접 사용하지 않고 서비스 계약으로 연결합니다"* 로 뒀어요. `target.current_deployment_target_id` 까지는 `project` 모듈(제 소유)이라 읽고, 그 ID 가 가리키는 `deployment_target` 행은 읽지 않아요. 그래서 `current` 블록이 지금 항상 null 이에요. 채우려면 deployment 쪽 조회 서비스 계약이 필요해요.
- **근거가 없는 필드를 값으로 채우지 않아요.** `url`·`health_summary`·`image_digest`·`current.image` 는 null, `health` 는 모른다는 뜻의 `unknown` 이에요. `roles.md` 66행(*"실제 응답에 없는 값을 만들어 제공하지 않습니다"*)과 승환이 #13 에 쓴 *"확인하지 못한 토큰·비용은 0으로 채우지 않고"* 와 같은 기준이에요.
- **`current` 가 없을 때 빈 객체를 보내지 않아요.** "배포가 없다" 와 "배포가 있는데 값이 비었다" 는 다른 사실이에요. 통째로 null 로 둬서 소비자가 구분할 수 있게 했어요.
- **접근 판정을 질의보다 먼저 해요.** 없는 프로젝트와 권한 없는 프로젝트가 모두 404 라, 판정이 막으면 질의가 아예 돌지 않아야 응답 시간으로도 존재가 새지 않아요. 테스트로 고정했어요.
- **질의 자체가 `project_id` 로 걸러요.** 호출 전에 접근 판정을 하더라도 질의가 프로젝트 경계를 넘지 않아야 다른 프로젝트의 대상이 섞이지 않아요.
- **정렬을 `(environment_type, name)` 으로 고정했어요.** 화면에서 환경 순서가 요청마다 바뀌지 않게 하려는 거예요.
- **데모 대상의 `connection_state` 를 `unknown` 으로 심어요.** 실제 연결 확인을 한 적이 없는데 `connected` 로 심으면 확인하지 않은 상태를 확인한 것처럼 보여 주게 돼요.
- 목록 봉투는 기존 `GET /projects` 와 같은 `{ items, next_cursor }` 예요. 승환이 S1 에서 *"목록은 전부 items/next_cursor, 비페이지 목록은 next_cursor=null"* 로 제안한 것과 같아요.

## 인계와 제한

- **`current` 블록을 채우려면 deployment 모듈의 조회 서비스가 필요해요.** 대상 ID 로 "마지막으로 끝난 배포의 `deployment_id`·`commit`·`finished_at`" 을 돌려주는 읽기 계약을 주시면 붙이겠어요. 제가 `deployment_target` 을 직접 읽는 쪽은 소유 경계를 넘어서 택하지 않았어요.
- **`url`·`health`·`health_summary`·`image_digest` 는 인프라 산출물 대기예요.** #17 의 `apply-result.json`(환경별 `service_url`·상태 코드·응답 시간)과 빌드 수신(A-06)이 생긴 뒤에 채워요. 어느 것도 기본값으로 채우지 않아요.
- **`connection_state` 를 계약에 없는데 추가했어요.** `TargetStatus` 에 없지만 W-04 가 *"연결 안 되는 환경은 고를 수 없어요"* 를 하려면 필요해요. 소비자 확인이 필요하면 말씀 주세요.
- **#13 의 `title` 은 넣지 않았어요.** WR-04 가 요청한 `title`("home-lab · Docker")은 `environment_type` 과 config 를 조립한 표시 문자열이라 화면 몫으로 봤어요. 승환이 S8 에서 "target title 제공" 으로 제안했으니, 서버가 조립하는 쪽으로 정하면 붙이겠어요.
- 데모 대상 시딩은 실제 저장소·대상 등록 절차가 정해지면 걷어내요.
- 커서 페이지네이션은 넣지 않았어요. 대상이 많아지면 `(environment_type, name)` 기준 커서를 붙여요.
- SSE 로 같은 정보를 밀어 주는 것은 승환의 재생 기반 위에 붙여요. 앱은 D2 에 5초 폴링으로 써요.

## 검증 결과

검사 항목을 먼저 적고 그대로 돌렸어요. 빈 PostgreSQL 17 에 띄워 실제 요청으로 확인했어요.

| | 검사 | 결과 |
|---|---|---|
| V1 | 토큰 없이 호출 | 401 |
| V2 | 없는 프로젝트 | 404 |
| V3 | 멤버가 아닌 프로젝트 | **404** (`NOT_FOUND`). 403 이 아니에요 |
| V4 | `viewer` 계정 조회 | 200 |
| V5 | 응답 봉투 | `{ items, next_cursor }`, `next_cursor` 는 null, 필드가 snake_case |
| V6 | 대상이 없는 프로젝트 | `{"items":[],"next_cursor":null}` — 오류가 아니에요 |
| V7 | 배포 이력이 없는 대상 | `current` null, `health` `"unknown"`, `url`·`health_summary`·`image_digest`·`checked_at` null |
| V8 | 보관된 대상 | `archived_at` 을 넣은 대상이 목록에서 빠졌어요 |
| V9 | 정렬 | `aws → gcp → onprem` 으로 고정 |
| V10 | **다른 프로젝트의 대상** | 다른 프로젝트에 대상을 넣고 확인했어요. 섞이지 않아요 |
| V11 | OpenAPI | 경로와 `PageResponseTargetStatusResponse`·`TargetStatusResponse`·중첩 `Current` 스키마가 노출돼요 |

- 단위 테스트 4개: 접근 판정이 막으면 **대상 질의가 아예 돌지 않는 것**, 대상 0개가 빈 목록인 것, 근거 없는 필드가 null 인 것, `viewer` 조회예요.
- `./gradlew --no-daemon spotlessApply spotlessCheck check build` 성공.
- 데모 대상 3개가 `connection_state='unknown'` 으로 심기는 것을 DB 에서 직접 확인했어요.

**확인하지 않은 것**

- `current` 가 채워진 응답은 확인하지 못했어요. 실행 서비스와 조회 계약이 없어 채울 경로가 없어요.
- 커서 페이지네이션, 대상이 많을 때의 성능, SSE 경로는 이번 범위가 아니에요.
- 원격 push 와 PR 은 하지 않았어요.
