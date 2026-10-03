# APNs 푸시 알림 (P-01 · P-02)

앱(iOS · macOS)이 승인 요청과 배포 결과를 푸시로 받게 해요. 계약은 [ios/SPEC.md §6-5](../../ios/SPEC.md)(9/29 합의)를 그대로 따르고, 코드는 전부 `com.teamdaisy.server.push` 패키지와 `V4__push_devices.sql` 에만 있어요. 실행부(`deployment/` · `history/`) 코드는 바꾸지 않았어요.

## 마이그레이션 번호

V3 은 일부러 비워 둔 번호예요(팀이 건너뜀). 푸시는 `V4__push_devices.sql`, 회원가입은 `V5__signup.sql` 이고, Flyway 는 번호가 비어도 괜찮아요. 앞으로 V3 을 새로 쓰지 않아요.

- `AzureMigrationPostgresTest` 는 두 번째 Flyway 에 `.target("2")` 를 붙여 V1 → V2 업그레이드만 확인해서, 뒤 번호가 늘어도 고칠 필요가 없어요.

## API

둘 다 Bearer 인증이 필요해요. 역할은 상관없어요(읽기 전용 `viewer` 계정도 알림은 받아요). 토큰을 URL 경로에 넣으면 서버 · 프록시 로그에 남아서 해제도 본문으로 받아요.

| 요청 | 본문 | 응답 |
|---|---|---|
| `POST /devices` | `{ "apns_token": "<hex>", "platform": "ios" \| "macos", "apns_env": "production" \| "sandbox" }` | 204 |
| `DELETE /devices` | `{ "apns_token": "<hex>" }` | 204 |

- `apns_token` 은 16진수 32~200자예요. 대소문자는 받되 소문자로 저장해요. 그 밖의 값 · 다른 `platform` · `apns_env` · 빈 본문은 400 `VALIDATION_FAILED`, 인증이 없으면 401 이에요.
- 등록은 토큰 기준 upsert 예요. 같은 토큰을 다시 보내면 지금 로그인한 계정으로 옮기고 `platform` · `apns_env` 를 바꾸며, APNs 가 거절해 꺼져 있던 기기도 다시 켜요.
- 해제는 멱등이에요. 내 계정에 묶인 토큰만 지우고, 모르는 토큰이나 다른 계정의 토큰이면 아무것도 바꾸지 않고 204 예요.
- TestFlight · 배포 빌드는 `production`, Xcode 에서 바로 설치한 개발 빌드는 `sandbox` 예요.

## 환경변수

`application.yml` 은 건드리지 않고 `@Value("${…:기본값}")` 로 바로 읽어요. 키는 커밋하지 않고 비밀 환경변수로만 넣어요.

| 이름 | 기본값 | 설명 |
|---|---|---|
| `DAISY_APNS_KEY` | (없음) | `.p8` 키 PEM 원문. 한 줄로 넣을 때는 줄바꿈을 `\n` 으로 써도 돼요 |
| `DAISY_APNS_KEY_PATH` | (없음) | `.p8` 파일 경로. `DAISY_APNS_KEY` 가 비어 있을 때만 읽어요 |
| `DAISY_APNS_KEY_ID` | (없음) | APNs 키 ID (JWT `kid`) |
| `DAISY_APNS_TEAM_ID` | `X5F5WM2H6M` | Apple 팀 ID (JWT `iss`) |
| `DAISY_APNS_TOPIC` | `com.teamdaisy.daisy` | `apns-topic`. 앱 번들 ID |
| `daisy.push.dispatch-delay-ms` | `5000` | 발송 주기(선택) |

키와 키 ID 가 둘 다 있어야 켜져요. 없거나 키를 읽지 못하면 기동 때 `push_disabled reason=…` 로그를 한 번 남기고, 발송기는 보내지 않고 커서만 끝으로 옮겨요. 그래서 나중에 키를 넣어도 지난 이벤트가 한꺼번에 나가지 않아요. 키 원문 · 경로 · 기기 토큰 전체는 로그에 남기지 않아요(토큰은 끝 6자리만).

## 발송 동작

`PushDispatcher` 가 5초마다 한 번 돌아요(`@EnableScheduling` 은 Jenkins 워커가 꺼져 있으면 켜지지 않아서 `PushConfiguration` 에서도 켜요).

1. **원본은 `deployment_log`.** `approval.required` · `deployment.completed` 는 `EventJournal` 이 `project_event` 로 옮기지 않는 종류라(옮기는 것은 `build.received` · `deployment.created` · `target.status_changed` 뿐) `project_event` 에서는 보이지 않아요. 그래서 `deployment_log` 를 읽기 전용으로 읽고 `processing_result='applied'` 인 행만 써요.
2. **커서.** 트랜잭션 안에서 `push_cursor` 행을 `SELECT … FOR UPDATE` 로 잡고, `id > 커서` 를 id 순서로 최대 200건 읽고, 커서를 옮긴 뒤 커밋해요. 서버가 여러 대여도 같은 이벤트를 두 번 가져가지 않아요. 커서 행이 없으면(첫 실행) 지금의 `max(id)` 로 만들고 그 주기는 보내지 않아요.
3. **늦게 커밋되는 행 대비.** id 는 insert 순서지만 커밋 순서는 다를 수 있어요. 2초 안에 들어온 행이 있으면 그 앞까지만 읽고 다음 주기에 이어서 읽어요. 쓰기 트랜잭션이 2초 안에 끝난다는 가정의 최선 노력이고, 그보다 오래 걸린 트랜잭션의 행은 드물게 놓칠 수 있어요. 대신 알림이 최대 7초쯤 늦을 수 있어요.
4. **오래된 이벤트.** `occurred_at` 이 10분보다 오래되면 보내지 않고 커서만 지나가요.
5. **묶기.** `approval.required` 는 대상마다 하나씩 생겨서, 한 묶음 안에서 배포당 알림 하나로 줄여요. `deployment.completed` 는 payload `status`(배포 최종 상태)로 kind 를 골라요.
6. **받는 사람.** 그 프로젝트를 볼 수 있는 계정의 켜진 기기 전부예요. 기준은 `ProjectAccessService.requireRead` · `AuthService.resolve` 와 같게 SQL 로 읽어요: 보관되지 않은 프로젝트, `revoked_at` 이 없는 멤버십, `disabled_at` 이 없는 계정.
7. **발송은 트랜잭션 밖.** 커밋한 뒤 APNs 로 한 번만 보내요. 실패는 로그만 남기고 다시 시도하지 않아요. 알림은 놓칠 수 있어도 커서는 멈추지 않아요.

| 이벤트 | 조건 | `kind` | 문구 키(`title-loc-key` / `loc-key`) | `apns-collapse-id` |
|---|---|---|---|---|
| `approval.required` | 배포당 1건 | `approval_required` | `push.approval.title` / `push.approval.body` | `approval-<deployment_id>` |
| `deployment.completed` | `succeeded` | `deployment_succeeded` | `push.succeeded.title` / `push.succeeded.body` | `result-<deployment_id>` |
| `deployment.completed` | `partially_succeeded` | `deployment_partially_succeeded` | `push.partial.title` / `push.partial.body` | `result-<deployment_id>` |
| `deployment.completed` | `failed` | `deployment_failed` | `push.failed.title` / `push.failed.body` | `result-<deployment_id>` |
| `deployment.completed` | `cancelled` · 그 밖 | 보내지 않아요 | | |

payload 예시예요. 문구는 앱이 String Catalog 로 현지화하고, `loc-args[0]` 은 프로젝트 이름이에요.

```json
{ "aps": { "alert": { "title-loc-key": "push.approval.title", "loc-key": "push.approval.body", "loc-args": ["sample-monolith"] },
           "sound": "default", "thread-id": "prj_demo_monolith" },
  "kind": "approval_required", "project_id": "prj_demo_monolith", "deployment_id": "dep_…" }
```

### APNs 요청

- `POST https://api.push.apple.com/3/device/<token>` (`production`) 또는 `https://api.sandbox.push.apple.com/3/device/<token>` (`sandbox`), JDK `HttpClient` HTTP/2.
- 헤더 `authorization: bearer <JWT>`, `apns-topic`, `apns-push-type: alert`, `apns-priority: 10`, `apns-collapse-id`(64바이트를 넘으면 뺌).
- JWT 는 ES256(`SHA256withECDSAinP1363Format`), 헤더 `{alg: ES256, kid}`, 클레임 `{iss: 팀 ID, iat}`. 50분마다 새로 서명하고, `403 ExpiredProviderToken` 을 받으면 다음 요청에서 새로 서명해요.
- 응답: 200 성공. `410`, 또는 `400` 의 `BadDeviceToken` · `Unregistered` · `DeviceTokenNotForTopic` 이면 기기를 꺼요(행은 남기고 `disabled_at` · `last_error` 기록). 그 밖은 로그만 남겨요.

## 테이블 (V4)

- `push_device(apns_token PK, account_id → account, platform, apns_env, created_at, updated_at, disabled_at, last_error)` — CHECK 로 API 와 같은 값만 받아요.
- `push_cursor(name PK, last_id, updated_at)` — 지금은 `name='deployment_log'` 한 행이에요.

## 검증

- `PushDeviceControllerTest` — 입력 검증 400, 인증 401, viewer 등록 (DB 없음)
- `PushDevicePostgresTest` — 등록 · 재등록 소유자 이동 · 다시 켜기, 내 토큰만 해제, V4 제약
- `PushDispatcherPostgresTest` — 배포당 승인 1건, 완료 상태 매핑 · 취소 제외, 커서 초기화, 10분 지난 이벤트, 늦은 행 대기, 키 없음, `BadDeviceToken` · `410` 기기 끄기, 받는 사람 기준
- `PushMessagesTest` · `ApnsJwtTest` · `ApnsClientTest` — payload 모양, JWT 서명 검증 · 캐시, 키 설정, 요청 헤더 · 응답 해석(로컬 HTTP 서버)
- 로컬 jar 로 가짜 키를 넣고 sandbox 에 실제로 보내 `403 InvalidProviderToken` 응답을 받는 것까지 확인했어요. 실제 키로 기기에 도착하는지는 키를 넣은 뒤 확인이 필요해요.
