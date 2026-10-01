# Team Daisy 결정 보드

슬랙 · 노션 · 깃에서 **팀이 결정한 것만** 시간순으로 모아요. 파트 구분 없이 한 줄씩 적고, 30분마다 전담 에이전트가 갱신해요.

> 10/1부터 레포 루트의 팀 공용 파일이에요 (`ios/BOARD.md`에서 옮김). 서비스 이름은 Unibloom, 팀 이름은 Team Daisy 그대로예요. 9/28–10/1 링크의 `…/daisy/…` 주소는 `…/unibloom/…`로 자동 이동해요.

## 작성 지침

1. **결정만 적어요.** 회의 합의, 담당 파트의 확정(결정 기록 · 머지된 PR · "확정"/"넣을게요" 같은 명시적 답)만요. 제안 · 질문 · 진행 상황 · 아무도 받지 않은 `(가칭)`은 적지 않아요.
2. **출처가 있어야 해요.** 줄마다 슬랙 · 노션 · 깃 링크를 달아요. 링크가 없으면 적지 않아요.
3. **미정이 정해지면 미정을 남기지 않아요.** 정해진 시각의 칸에 결정으로 적고, 보드 어디에도 미정으로 남기지 않아요.
4. **번복은 지우지 않아요.** 이전 줄은 ~~취소선~~ + `→ 번복: 날짜 칸`으로 두고, 새 결정은 그 시각의 칸에 새로 적어요.
5. **시간 기준은 KST예요.** 날짜별 오전(00:00–11:59) · 오후(12:00–23:59) 칸으로 묶고, 결정이 난 시각(메시지 · 회의 · 머지)으로 넣어요.
6. **한 줄 형식:** `- HH:MM [파트] 결정 — [출처](링크)`. 파트: 팀 · 웹 · 앱 · 서버 · 인프라 · CI · 샘플.
7. **비밀값 · 개인 연락처는 적지 않아요.**

상태: 마지막 갱신 2026-10-01 21:55 KST · 확인한 범위 Slack ~21:55 / Notion ~21:55 / GitHub ~21:55 (21:27–21:55: 10/1 회의(허들 20:57–21:51) 결과 중 슬랙 · 깃에 남은 결정 6건 반영 · 1건 번복(9/30 21:38 도메인 `daisydeploy.dev` → `unibloom.cloud`). **10/1 허들 AI 메모 캔버스는 아직 안 올라왔고**, 노션 「10/01 Meeting」은 안건뿐(21:05 수정) — 레지스트리 Docker Hub 팀 확정 · AI 생성 담당 최종 확인 · Claude API 키 주인 · 서버 최소 연결 흐름 · 10/2 리허설 · 시연 · 발표 담당은 회의 결과 출처가 없어 미반영, 메모가 올라오면 다음 갱신에서 반영; 21:52 황지환 → 박승준 질문("서버 연결 포함해서 24시까지인지, 도메인 구매만 24시까지인지")은 답 전이라 미반영; PR #37 · #33 · #25 · #23 리뷰 요청(21:51)만, 머지 없음)

## 결정 기록

### 9/28 (월) 오후

- 21:37 [팀] 팀장은 김도영 — [노션](https://app.notion.com/p/3e98bee9ada4804ab1a2e9817314047e)
- 21:37 [팀] 예선 전까지 매일 21:00–22:00 온라인 정기 회의(Slack 허들), 문서는 Notion · 소통은 Slack — [노션](https://app.notion.com/p/3e98bee9ada4804ab1a2e9817314047e)
- 21:37 [팀] 역할: 웹 FE 김도영·박승준 / 웹 BE 하은현·김승환 / 인프라 온프레미스 황지환 · 클라우드 임채준 (ADR-001) — [노션](https://app.notion.com/p/3e98bee9ada4804ab1a2e9817314047e)

### 9/29 (화) 오전

- 03:12 [팀] 주제: AI 기반 온프레미스·퍼블릭 클라우드 원터치 배포 시스템 (ADR-002) — [노션](https://app.notion.com/p/fe08bee9ada482d2901281a1d7c15c13)
- 03:12 [인프라] IaC는 Terraform (ADR-003) — [노션](https://app.notion.com/p/fe08bee9ada482d2901281a1d7c15c13)
- 03:12 [CI] 앱 입력은 GitHub 저장소 + main merge → ~~GitHub Actions 빌드~~, 이미지 태그는 커밋 해시 (ADR-004) — [노션](https://app.notion.com/p/fe08bee9ada482d2901281a1d7c15c13) → 번복: 9/30 오후 (빌드·배포는 Jenkins)
- 03:12 [인프라] 온프레미스 런타임은 Docker (ADR-005) — [노션](https://app.notion.com/p/fe08bee9ada482d2901281a1d7c15c13)
- 03:12 [웹] 프론트는 React + Vite SPA, 최소 스택으로 시작하고 막힐 때만 추가 (ADR-006) — [노션](https://app.notion.com/p/fe08bee9ada482d2901281a1d7c15c13)

### 9/29 (화) 오후

- 12:11 [팀] 웹은 김도영, Swift 앱은 박승준이 전담 — [슬랙 DM](https://softbankhackathon2026.slack.com/archives/D0C53LJJ6TY/p1790651467970789)
- 12:44 [샘플] HelloCalc를 고정 reference workload(`sample-monolith`)로 사용 — [슬랙](https://softbankhackathon2026.slack.com/archives/C0C1YSY25LZ/p1790653467434369)
- 14:50 [앱] SwiftUI 멀티플랫폼(iOS·macOS 한 타깃), 서드파티 패키지 없이 시작 — [PR #1](https://github.com/Softbank-Hackathon-2026-Team-Daisy/daisy/pull/1)
- 14:50 [앱] ~~최소 iOS 17 · macOS 14~~ — [PR #1](https://github.com/Softbank-Hackathon-2026-Team-Daisy/daisy/pull/1) → 번복: 9/30 오후
- 14:50 [앱] ~~목업 모드 없이 항상 실서버 사용~~ — [PR #1](https://github.com/Softbank-Hackathon-2026-Team-Daisy/daisy/pull/1) → 번복: 9/30 오후
- 14:50 [앱] SSE는 `URLSession.bytes`로 읽고, 토큰은 Keychain에 저장 — [PR #1](https://github.com/Softbank-Hackathon-2026-Team-Daisy/daisy/pull/1)
- 16:49 [CI] 모든 레포 main 보호(protect-main 규칙셋): 직접·force push 금지, PR + squash만, daisy는 승인 1명 — [슬랙](https://softbankhackathon2026.slack.com/archives/C0C1YSY25LZ/p1790668194490609)
- 16:49 [CI] org Owner는 김도영만, 파트별 팀에 세 레포 Write 권한 — [슬랙](https://softbankhackathon2026.slack.com/archives/C0C1YSY25LZ/p1790668194490609)
- 16:49 [샘플] `sample-monolith` · `sample-msa`는 PR 후 셀프 머지 가능, 10/3~4는 모든 레포 셀프 머지 허용 — [슬랙](https://softbankhackathon2026.slack.com/archives/C0C1YSY25LZ/p1790668194490609)
- 18:07 [CI] CODEOWNERS: `server/`는 server 팀, `infra/`는 infra 팀 승인이 있어야 머지 — [PR #3](https://github.com/Softbank-Hackathon-2026-Team-Daisy/daisy/pull/3)
- 20:02 [서버] 인증은 REST·SSE 모두 Bearer 토큰 하나 (쿠키 안 받음) — [PR #1 리뷰](https://github.com/Softbank-Hackathon-2026-Team-Daisy/daisy/pull/1#pullrequestreview-5351524196)
- 20:02 [서버] 앱이 요청한 API 이름 확정(`POST /auth/token`, `targets/status` 별도, `builds`, `logs`, SSE 채널·이벤트), 기기 해제는 `DELETE /devices` + 본문 — [PR #1 리뷰](https://github.com/Softbank-Hackathon-2026-Team-Daisy/daisy/pull/1#pullrequestreview-5351524196)
- 20:02 [서버] 승인 대기 목록은 별도 API 없이 배포 목록의 `awaiting_approval` 필터로 — [PR #1 리뷰](https://github.com/Softbank-Hackathon-2026-Team-Daisy/daisy/pull/1#pullrequestreview-5351524196)
- 20:02 [서버] `attempt`는 환경별, 최초 생성 포함 총 3회(AI 수정 최대 2번), 화면 표기 "시도 n/3" — [PR #1 리뷰](https://github.com/Softbank-Hackathon-2026-Team-Daisy/daisy/pull/1#pullrequestreview-5351524196)
- 20:02 [서버] plan 요약은 `counts` · `has_delete` · `risks`, AI 비용은 plan에 넣지 않고 `ai_usage` 합산으로 — [PR #1 리뷰](https://github.com/Softbank-Hackathon-2026-Team-Daisy/daisy/pull/1#pullrequestreview-5351524196)
- 20:02 [서버] SSE 전(D3)까지 웹·앱은 5초 폴링, 푸시 전에는 로컬 알림 — [PR #1 리뷰](https://github.com/Softbank-Hackathon-2026-Team-Daisy/daisy/pull/1#pullrequestreview-5351524196)
- 20:02 [서버] API 계약의 단일 원천은 서버 OpenAPI, 노션 「Backend API Endpoint」는 합의 기록 — [PR #1 리뷰](https://github.com/Softbank-Hackathon-2026-Team-Daisy/daisy/pull/1#pullrequestreview-5351524196)
- 20:44 [서버] Spring Boot 3.5.16 · Java 21 · 단일 모듈, 정적 분석은 Spotless만 — [PR #6](https://github.com/Softbank-Hackathon-2026-Team-Daisy/daisy/pull/6)
- ~~20:44 [서버] 작업 큐는 Postgres(`FOR UPDATE SKIP LOCKED`), 인스턴스 2대 이상이면 Redis로~~ — [PR #6](https://github.com/Softbank-Hackathon-2026-Team-Daisy/daisy/pull/6) → 번복: 10/1 오후 (Postgres는 Jenkins 명령 · 폴링 · 복구 기록, 인스턴스 수만으로 Redis 전환 안 함)
- ~~20:44 [서버] `terraform apply` 실행·상태·락·SSE는 하은현, 생성·검증·공통 Terraform CLI 실행부는 김승환~~ — [PR #6](https://github.com/Softbank-Hackathon-2026-Team-Daisy/daisy/pull/6) → 번복: 9/30 오후 (Terraform 생성·실행은 Jenkins CD, 인프라 담당)
- 20:44 [서버] 한 환경이 3회 실패해도 나머지 환경은 계속 진행 (Q7) — [PR #6](https://github.com/Softbank-Hackathon-2026-Team-Daisy/daisy/pull/6)
- 20:44 [서버] plan이 stale되면 다시 plan → 재승인, 이때 `attempt`는 올리지 않음 — [PR #6](https://github.com/Softbank-Hackathon-2026-Team-Daisy/daisy/pull/6)
- 20:44 [서버] 락은 같은 Terraform state를 쓰는 대상 기준, 승인 접수 시점부터 — [PR #6](https://github.com/Softbank-Hackathon-2026-Team-Daisy/daisy/pull/6)
- 20:44 [서버] 취소는 apply 전까지, 이후는 중단 요청 — [PR #6](https://github.com/Softbank-Hackathon-2026-Team-Daisy/daisy/pull/6)
- 20:44 [서버] JSON은 전역 `snake_case` — [PR #6](https://github.com/Softbank-Hackathon-2026-Team-Daisy/daisy/pull/6)
- 20:44 [서버] AI 비용은 USD를 배포 단위로 합산 → 고정 환율로 원화 환산, "추정" + 적용 환율 표시, 확인 못 한 비용은 NULL — [PR #6](https://github.com/Softbank-Hackathon-2026-Team-Daisy/daisy/pull/6)
- 21:00 [팀] 에이전트 개발 방식: `daisy` 모노레포 하나, 파트 `AGENTS.md`, `SPEC.md` 먼저 → 구현 → SPEC 최신화 → PR — [노션](https://app.notion.com/p/3e98bee9ada480d68a41e6de6155225e)
- 21:00 [팀] 자기 영역은 자율 결정 후 Slack 공유, 다른 파트 수정은 직접 하지 않고 이슈·Slack으로 요청 — [노션](https://app.notion.com/p/3e98bee9ada480d68a41e6de6155225e)
- 21:00 [샘플] `sample-msa`는 프론트 컨테이너 1 + 백엔드 컨테이너 1, 박승준 담당 — [노션](https://app.notion.com/p/3e98bee9ada480d68a41e6de6155225e)
- 21:00 [서버] 도메인을 구매해서 HTTPS 적용 (~~하은현·김승환, 9/30 오후 전~~) — [노션](https://app.notion.com/p/3e98bee9ada480d68a41e6de6155225e) → 번복(담당): 9/30 오후
- 21:00 [인프라] 사설망(VPN)이 안 되면 빼고 온프레미스·클라우드를 각각 배포 — [노션](https://app.notion.com/p/3e98bee9ada480d68a41e6de6155225e)
- 21:00 [팀] 기능 구현 먼저, 시각화는 로딩 화면 등에 나중에 — [노션](https://app.notion.com/p/3e98bee9ada480d68a41e6de6155225e)
- 21:00 [팀] 파트 회의도 Slack 허들, 백엔드는 매일 18:00–19:00 — [노션](https://app.notion.com/p/3e98bee9ada480d68a41e6de6155225e)
- 21:00 [팀] 발표 담당은 10/3에 결정 — [노션](https://app.notion.com/p/3e98bee9ada480d68a41e6de6155225e)

### 9/30 (수) 오전

- 10:19 [서버] DB는 Flyway 마이그레이션 먼저 쓰고 엔티티를 맞춤, `V1__init.sql`부터 순차, 적용된 파일은 고치지 않음 — [PR #7](https://github.com/Softbank-Hackathon-2026-Team-Daisy/daisy/pull/7#issuecomment-5902172166)
- 10:48 [팀] 30만 원 예산 견적(도영 안) 합의, 클라우드 비용은 규모 보며 추가 — [슬랙](https://softbankhackathon2026.slack.com/archives/C0C1YSY25LZ/p1790732887179559)

### 9/30 (수) 오후

- 14:50 [앱] 반응형 코드베이스 하나, 최소 iOS 18 · macOS 15, 폭 기준 레이아웃 — [PR #8](https://github.com/Softbank-Hackathon-2026-Team-Daisy/daisy/pull/8)
- 15:10 [앱] 웹과 같이 쓰는 기능은 흐름·문구·`+/~/-` 표기를 웹에 맞춤 — [PR #8](https://github.com/Softbank-Hackathon-2026-Team-Daisy/daisy/pull/8)
- 15:17 [웹] 브라우저 SSE는 `fetch` 스트리밍 + `Authorization` 헤더 (서버 16:48 확인) — [슬랙](https://softbankhackathon2026.slack.com/archives/C0C1YSY25LZ/p1790749066946749?thread_ts=1790748785.163079&cid=C0C1YSY25LZ)
- 15:21 [앱] Figma에서는 문구만 가져오고 색·모양은 앱 디자인 유지, 메뉴·상태 라벨은 웹과 동일 — [PR #8](https://github.com/Softbank-Hackathon-2026-Team-Daisy/daisy/pull/8)
- 16:27 [웹] UI 기준은 Figma 와이어프레임 v1.0 · 디자인 시스템 — [PR #9](https://github.com/Softbank-Hackathon-2026-Team-Daisy/daisy/pull/9)
- 16:27 [웹] TypeScript + CSS 변수 토큰, UI 키트·차트 라이브러리 없음 — [PR #9](https://github.com/Softbank-Hackathon-2026-Team-Daisy/daisy/pull/9)
- 16:27 [웹] 목업(MSW) 허용, `src/mocks/`에만 두고 화면에 항상 표시 — [PR #9](https://github.com/Softbank-Hackathon-2026-Team-Daisy/daisy/pull/9)
- 16:33 [웹] `react-router` 사용, Node 22 LTS · pnpm 9 고정 — [PR #9](https://github.com/Softbank-Hackathon-2026-Team-Daisy/daisy/pull/9)
- 16:36 [인프라] AWS는 ECS Fargate + ALB, 태스크는 public 서브넷 + 공인 IP, NAT 없음 — [PR #12](https://github.com/Softbank-Hackathon-2026-Team-Daisy/daisy/pull/12)
- 16:36 [인프라] 클라우드 구현 순서 AWS → GCP — [PR #12](https://github.com/Softbank-Hackathon-2026-Team-Daisy/daisy/pull/12)
- 16:36 [인프라] 팀원 서버 연결 전까지 Mac VM(`daisy-runner`)에서 Jenkins CI·CD 프로토타입, 개인 계정·Docker Hub 사용 — [PR #12](https://github.com/Softbank-Hackathon-2026-Team-Daisy/daisy/pull/12)
- 16:36 [인프라] CI 이미지는 `linux/amd64` · `linux/arm64` 멀티 아키텍처로 푸시 — [PR #12](https://github.com/Softbank-Hackathon-2026-Team-Daisy/daisy/pull/12)
- 16:36 [인프라] apply·destroy는 사람 승인(`TF_RUN_APPROVED`) 뒤에만 실행 — [PR #12](https://github.com/Softbank-Hackathon-2026-Team-Daisy/daisy/pull/12)
- 16:36 [인프라] 클라우드는 최소 비용 기본값: 로그 보존 3일, 삭제 보호 끔, Secrets Manager 복구 기간 0일 — [PR #12](https://github.com/Softbank-Hackathon-2026-Team-Daisy/daisy/pull/12)
- 16:48 [서버] 배포 상태 두 층: 전체 7개(`partially_succeeded` 포함, 우선순위 규칙) · 환경별 9개, step 6개(`health_check` 포함) — [슬랙](https://softbankhackathon2026.slack.com/archives/C0C1YSY25LZ/p1790754523730859?thread_ts=1790748785.163079&cid=C0C1YSY25LZ)
- 16:48 [서버] 데모 계정(`viewer`)은 조회만·승인 403, GitHub는 저장소 연결에만(OAuth 로그인 없음) — [슬랙](https://softbankhackathon2026.slack.com/archives/C0C1YSY25LZ/p1790754523730859?thread_ts=1790748785.163079&cid=C0C1YSY25LZ)
- 16:48 [서버] SSE: `id` = 채널별 1부터 시작하는 `seq`, `Last-Event-ID`로 재연결, heartbeat 15초, CORS 허용 헤더 확정 — [슬랙](https://softbankhackathon2026.slack.com/archives/C0C1YSY25LZ/p1790754523730859?thread_ts=1790748785.163079&cid=C0C1YSY25LZ)
- 16:48 [서버] v0.1 API 중 소스 업로드·analysis·IR 편집·추천·관측·카나리 제외, 검증 오류 코드는 `MANIFEST_INVALID` — [슬랙](https://softbankhackathon2026.slack.com/archives/C0C1YSY25LZ/p1790754523730859?thread_ts=1790748785.163079&cid=C0C1YSY25LZ)
- 17:02 [서버] 배포 시작은 `POST /projects/{id}/deployments` — [PR #9](https://github.com/Softbank-Hackathon-2026-Team-Daisy/daisy/pull/9#issuecomment-5906869022)
- 17:02 [서버] `source_version`에 `image_digest` 추가(웹훅으로 받음), 이미지 동일성 근거로 사용 — [PR #9](https://github.com/Softbank-Hackathon-2026-Team-Daisy/daisy/pull/9#issuecomment-5906869022)
- 17:02 [서버] 롤백 포함: 이전 성공 커밋 + 검증된 스크립트로 만드는 새 배포(`kind: rollback`), 환경 선택 가능, plan 승인 필수 — [PR #9](https://github.com/Softbank-Hackathon-2026-Team-Daisy/daisy/pull/9#issuecomment-5906869022)
- 17:02 [서버] 환경 선택용 `GET /projects/{id}/targets`는 `targets/status`와 별도, 프로젝트 삭제는 연결만 해제 — [PR #9](https://github.com/Softbank-Hackathon-2026-Team-Daisy/daisy/pull/9#issuecomment-5906869022)
- 17:09 [웹] W-02b 소스 업로드는 범위 제외, 입력은 GitHub 저장소 연결만 — [슬랙 DM](https://softbankhackathon2026.slack.com/archives/D0C53LJJ6TY/p1790755760077179)
- 17:09 [웹] W-05b 한 환경 실패 시 "○○만 다시 시도", "빼고 계속" 버튼은 없앰 — [슬랙 DM](https://softbankhackathon2026.slack.com/archives/D0C53LJJ6TY/p1790755760077179)
- 17:09 [웹] W-12 AI 사용량은 배포를 하나 골라서 보는 배포 단위 구조로 — [슬랙 DM](https://softbankhackathon2026.slack.com/archives/D0C53LJJ6TY/p1790755760077179)
- 17:18 [앱] 공용 화면은 웹 `WR-xx` 요청과 서버 두 층 상태를 그대로 사용, 재시도는 같은 커밋의 새 배포 — [PR #8](https://github.com/Softbank-Hackathon-2026-Team-Daisy/daisy/pull/8)
- 17:18 [웹] 웹에 Mac 앱 다운로드(W-14) 진입점 추가 — [슬랙 DM](https://softbankhackathon2026.slack.com/archives/D0C53LJJ6TY/p1790756305949379)
- 17:22 [인프라] Terraform plan 파일 이름은 `plan.tfplan` — [PR #10](https://github.com/Softbank-Hackathon-2026-Team-Daisy/daisy/pull/10)
- 17:24 [서버] `ir` 조회 계약 없음(입력 스냅샷만 저장), `patch` 대신 `script` 테이블, 빌드 이벤트는 `build.received`로 통일 — [PR #7](https://github.com/Softbank-Hackathon-2026-Team-Daisy/daisy/pull/7#issuecomment-5907221966)
- 17:24 [서버] API 시간은 ISO 8601 UTC, 원화 금액은 정수, 상태·단계는 문자열(모르는 값에도 실패하지 않게) — [노션](https://app.notion.com/p/3eb8bee9ada48037ac7ee75f05a3841f)
- 17:33 [샘플] 로컬 이미지 태그도 커밋 해시로 통일(`latest` 제거) — [sample-monolith PR #1](https://github.com/Softbank-Hackathon-2026-Team-Daisy/sample-monolith/pull/1)
- 17:33 [샘플] Cloud Run backend는 인증 없는 호출 허용 + `internal` ingress로 외부 차단 — [sample-msa PR #2](https://github.com/Softbank-Hackathon-2026-Team-Daisy/sample-msa/pull/2)
- ~~17:44 [서버] plan 상세(환경별 리소스 · 변경 동작)와 생성된 Terraform 파일 조회 산출물은 김승환이 제공, API 연결은 하은현과~~ — [PR #9](https://github.com/Softbank-Hackathon-2026-Team-Daisy/daisy/pull/9#issuecomment-5907560258) → 번복: 10/1 오후 (19:39, 인프라가 만들고 서버가 받아 보관 · 조회)
- 17:57 [앱] TestFlight 앱 이름 "Daisy Deploy"(홈 화면 이름은 Daisy), 빌드 번호는 `yyMMddHHmm` — [PR #8](https://github.com/Softbank-Hackathon-2026-Team-Daisy/daisy/pull/8)
- 18:09 [앱] TestFlight 그룹: 내부 `Team Daisy`(자동 배포), 외부 `Public Link`(베타 심사 후 공개) — [PR #8](https://github.com/Softbank-Hackathon-2026-Team-Daisy/daisy/pull/8)
- 18:55 [앱] Mac 직접 다운로드는 공증된 DMG를 `daisy` GitHub Releases(태그 `mac-v<버전>-<빌드>`, pre-release)에 올리고 웹 W-14가 연결 (웹 18:57 수락) — [PR #9](https://github.com/Softbank-Hackathon-2026-Team-Daisy/daisy/pull/9#issuecomment-5908805197)
- ~~19:46 [인프라] 개인 AWS 계정은 plan까지만(`ReadOnlyAccess` · Jenkins `PLAN_ONLY=1` · Zero spend budget), apply는 팀 계정에서~~ — [커밋](https://github.com/Softbank-Hackathon-2026-Team-Daisy/daisy/commit/de0e61f7ae6e3054656271bc75f19846f89a25da) → 번복: 10/1 오후 (팀 계정이 없어 개인 계정을 실제 환경으로)
- 20:25 [앱] 오프라인 예시 데이터 모드 추가: 로그인의 "예시 데이터로 둘러보기 (오프라인)", 화면마다 "예시 데이터" 배지, 읽기 전용, 실서버 데이터와 섞지 않음 (실서버가 기본) — [커밋](https://github.com/Softbank-Hackathon-2026-Team-Daisy/daisy/commit/beb95e6)
- 20:31 [팀] 루트 규칙은 영어 `AGENTS.md`(`CLAUDE.md` 대체), 결정 권한 4단계: 파트 안은 바로 확정 · 제공하는 계약은 결정 후 소비자에게 이슈 · 다른 파트는 담당자가 결정(요청은 `(가칭)` + 이슈) · 팀 사항은 `[결정]` 이슈 + 회의 — [PR #2](https://github.com/Softbank-Hackathon-2026-Team-Daisy/daisy/pull/2)
- 20:31 [팀] 다른 파트 변경은 PR이 아니라 이슈로 요청, 구현 전에 모순 확인 — [PR #2](https://github.com/Softbank-Hackathon-2026-Team-Daisy/daisy/pull/2)
- 20:32 [앱] 웹 W-14 Mac 다운로드는 고정 주소 `releases/download/mac-latest/Daisy.dmg`, 새 빌드는 파일만 교체 — [PR #9](https://github.com/Softbank-Hackathon-2026-Team-Daisy/daisy/pull/9#issuecomment-5910304737)
- 20:35 [웹] 상태 배지 색은 와이어프레임 기준, 매핑은 `api/status.ts` 한 곳 (승인 대기·대기 중·취소됨 회색, 일부 성공 주황, 롤백 성공 보라, 모르는 값은 회색 "알 수 없음") — [커밋](https://github.com/Softbank-Hackathon-2026-Team-Daisy/daisy/commit/6815b07)
- 20:35 [웹] 토큰은 메모리에만 두고 역할만 context로 (새로고침하면 다시 로그인) — [커밋](https://github.com/Softbank-Hackathon-2026-Team-Daisy/daisy/commit/6815b07)
- 20:35 [웹] 화면 경로는 `src/paths.ts` 한 곳에서 관리 (SPEC §2-6) — [커밋](https://github.com/Softbank-Hackathon-2026-Team-Daisy/daisy/commit/6815b07)
- 20:35 [웹] 전환 로딩 끝 신호: L-01 첫 빌드 도착 · L-02 배포가 `queued`를 벗어날 때 · L-03 한 환경이라도 `applying` 이후 — [커밋](https://github.com/Softbank-Hackathon-2026-Team-Daisy/daisy/commit/6815b07)
- 20:35 [웹] 서버가 선택 필드(`steps` 등)나 plan 원문을 안 주면 화면이 단계·상태로 추정하거나 "—", W-06은 리소스 목록만 — [커밋](https://github.com/Softbank-Hackathon-2026-Team-Daisy/daisy/commit/6815b07)
- 20:35 [웹] 롤백·연결 해제 확인 문구는 환경 이름 대신 프로젝트 이름 — [커밋](https://github.com/Softbank-Hackathon-2026-Team-Daisy/daisy/commit/6815b07)
- 21:00 [CI] CI/CD 도구는 GitHub Actions 대신 Jenkins로 확정 (숙련도 · 비용 이유, 9/30 회의) — [노션](https://app.notion.com/p/3e98bee9ada480fda11bd40f219c0dde)
- 21:00 [인프라] 배포 흐름: 백엔드는 apply 요청을 API로 Jenkins에 보내기만 하고, Jenkins CD job이 AI Terraform 생성 → validate·plan → apply → 온프레미스·AWS 배포까지 진행, 배포 위치·Terraform 실행·state는 인프라 담당 — [노션](https://app.notion.com/p/3e98bee9ada480fda11bd40f219c0dde)
- 21:00 [인프라] AI Terraform 생성 · 수정 루프 · 재사용 담당은 김승환 → 임채준 (Terraform 실행이 CI · CD 모두 Jenkins로 모여서, 9/30 회의 합의 · 10/1 15:35 임채준 기록) — [노션](https://app.notion.com/p/3e98bee9ada480fda11bd40f219c0dde) · [커밋](https://github.com/Softbank-Hackathon-2026-Team-Daisy/daisy/commit/f475ae6d99f80d50742e36536f20eb22d305848b)
- 21:00 [서버] DB는 PostgreSQL 확정 (JSON 다루기 편해서) — [노션](https://app.notion.com/p/3e98bee9ada480fda11bd40f219c0dde)
- 21:22 [팀] 데모 로그인: 로그인 안 하면 읽기 전용 둘러보기(화면만 보고 실행은 막음), 실제 실행은 심사위원에게 테스트 계정 1개 제공 (동시 실행으로 시연이 깨지는 것 방지) — [노션](https://app.notion.com/p/3e98bee9ada480fda11bd40f219c0dde)
- 21:27 [서버] LLM은 Claude (김승환 담당 영역 결정) — [슬랙](https://softbankhackathon2026.slack.com/archives/C0C1YSY25LZ/p1790771233456579)
- ~~21:38 [인프라] 도메인은 `daisydeploy.dev`~~, 구매 · HTTPS 연결은 인프라 황지환 담당 — [슬랙](https://softbankhackathon2026.slack.com/archives/C0C1YSY25LZ/p1790771917031649?thread_ts=1790769553.917499&cid=C0C1YSY25LZ) · [노션](https://app.notion.com/p/3e98bee9ada480fda11bd40f219c0dde) → 번복: 10/1 오후 (서비스 이름 Unibloom, 도메인 `unibloom.cloud`)
- 23:37 [팀] 첫 통합 범위는 AWS · DB 없는 단일 서비스 (온프레미스 · 클라우드를 같이 보여주는 최종 데모 범위는 유지, 김승환 질문에 팀장 답) — [슬랙](https://softbankhackathon2026.slack.com/archives/C0C1YSY25LZ/p1790779033482289?thread_ts=1790771233.456579&cid=C0C1YSY25LZ)
- 23:37 [인프라] 사용자 승인은 웹 · 앱 → 서버 승인 API 하나로 받고, Jenkins 쪽 별도 승인 단계는 실서비스에서 안 씀 (황지환 00:05 수락) — [슬랙](https://softbankhackathon2026.slack.com/archives/C0C1YSY25LZ/p1790779033482289?thread_ts=1790771233.456579&cid=C0C1YSY25LZ)
- 23:37 [인프라] Terraform 작업 폴더는 배포마다 분리, state는 `{project_id}/{target_id}` 고정 키 방향 (김승환 제안 · 팀장 동의, 최종 키 · 락 기준은 인프라가 확정) — [슬랙](https://softbankhackathon2026.slack.com/archives/C0C1YSY25LZ/p1790779033482289?thread_ts=1790771233.456579&cid=C0C1YSY25LZ)
- 23:37 [서버] 위험 검사: 차단 항목은 AI 수정 루프로, 경고는 승인 화면에서 확인 (규칙 이름 · 심각도 · 대상 리소스 · 메시지) (김승환 제안 · 팀장 동의) — [슬랙](https://softbankhackathon2026.slack.com/archives/C0C1YSY25LZ/p1790779033482289?thread_ts=1790771233.456579&cid=C0C1YSY25LZ)
- 23:51 [팀] 루트 `AGENTS.md` v1.2 머지: 9/29 회의와 파트별 결정(9/30 20:35까지)을 팀 공통 규칙에 반영 (21:00 회의 결정은 아직 미반영) — [PR #14](https://github.com/Softbank-Hackathon-2026-Team-Daisy/daisy/pull/14)

### 10/1 (목) 오전

- 00:29 [서버] 실패한 환경 재시도는 실패한 대상만 고른 새 배포(기존 이력 유지), 새 배포의 시도는 1/3부터 (경로 · 필드는 서버 OpenAPI 기준) — [이슈 #13](https://github.com/Softbank-Hackathon-2026-Team-Daisy/daisy/issues/13#issuecomment-5914420638)
- 00:29 [서버] AI 사용량의 `status`는 LLM 호출 성공 · 실패 (Terraform 검증 결과와 별개, 화면에는 "호출 성공 · 실패") — [이슈 #13](https://github.com/Softbank-Hackathon-2026-Team-Daisy/daisy/issues/13#issuecomment-5914420638)
- 00:29 [서버] 승인 화면의 AI 사용량 합계는 plan 응답(A-05)에 포함, 호출별 상세는 `GET /projects/{id}/ai-usage`의 `deployment_id` 필터로 (A-04 하나에 합계 · 상세를 담지 않음) — [이슈 #13](https://github.com/Softbank-Hackathon-2026-Team-Daisy/daisy/issues/13#issuecomment-5914420638)
- 00:36 [서버] 배포 생성 · 승인 · 롤백 POST는 `Idempotency-Key` 사용, 권한 부족 403 코드는 `FORBIDDEN` — [노션 v0.3](https://app.notion.com/p/3eb8bee9ada4803f98d7dedf872ae61e)
- 00:42 [인프라] 온프레미스 서비스 공개는 터널 대신 Route 53 → 공인 IP, 외부 80 · 443은 앱 요청용, HTTPS는 Let's Encrypt 인증서를 pfSense에 적용 (발급 · 갱신 · TLS 종료 방식은 미정) — [커밋](https://github.com/Softbank-Hackathon-2026-Team-Daisy/daisy/commit/d5088cf06099295560501808a341bcd66632d166)
- 01:21 [CI] Jenkins job은 `daisy-ci`(코드 → 테스트 · 이미지 빌드 → 레지스트리)와 ~~`daisy-cd`(이미지 → 온프레미스 · AWS 배포) 두 개~~, 서버는 Jenkins API로 요청하고 Terraform은 CI/CD VM의 Jenkins가 실행 (팀 합의, 황지환 기록) — [커밋](https://github.com/Softbank-Hackathon-2026-Team-Daisy/daisy/commit/1561fa5e6b68ebe17fe310479b0b458c8fa21580) → 번복: 10/1 오후 (CD는 `daisy-cd-plan` · `daisy-cd-apply` 두 Job)
- 01:21 [인프라] 온프레미스 데모는 미리 만든 Service VM의 Docker 컨테이너를 Terraform으로 관리(CI/CD VM → SSH), Proxmox VM 자동 생성은 후속 목표 — [커밋](https://github.com/Softbank-Hackathon-2026-Team-Daisy/daisy/commit/1561fa5e6b68ebe17fe310479b0b458c8fa21580)
- 01:21 [인프라] Docker Compose는 사용자 검증용만, 배포 컨테이너 · 네트워크 · 볼륨 관리는 Terraform 하나로 — [커밋](https://github.com/Softbank-Hackathon-2026-Team-Daisy/daisy/commit/1561fa5e6b68ebe17fe310479b0b458c8fa21580)
- 01:21 [인프라] 온프레미스 · 클라우드 Site-to-Site VPN 제외: AWS는 API로, 내부 Service VM은 SSH로 배포, WireGuard는 허용된 개발자 원격 접속용만 (황지환 · 임채준 합의) — [커밋](https://github.com/Softbank-Hackathon-2026-Team-Daisy/daisy/commit/1561fa5e6b68ebe17fe310479b0b458c8fa21580)
- 01:48 [인프라] 같은 Proxmox 서버 안에서 Service VM과 CI/CD VM을 분리하고, 서버가 승인받은 그 plan만 apply (승인 뒤 새로 만든 plan을 기존 승인으로 적용하지 않음) — [커밋](https://github.com/Softbank-Hackathon-2026-Team-Daisy/daisy/commit/1ec0b283f8ca179767cf7f4b5988fd0e456ad00e)
- 01:57 [인프라] 온프레미스 담당: 황지환은 Service VM 컨테이너 모듈 · Proxmox VM · 네트워크 분리 · pfSense 접근 제어 · WireGuard · HTTPS 공개, Jenkins 온프레미스 연결(SSH · Terraform 실행 환경 · 헬스체크 · 서버와 plan · 로그 · 중단 계약 협의)은 황지환 · 임채준 공동 — [커밋](https://github.com/Softbank-Hackathon-2026-Team-Daisy/daisy/commit/d627cf974c698ce064fc703d0388578573f84399)
- 04:59 [앱] 흐름 · 문구는 웹 화면 코드(PR #18)를 따름: 상태 라벨 · 단계 추정 · 시각 표기(24시간제 · 상대 시각)는 웹과 같게, 메뉴 "배포"는 가장 최근 배포의 지금 단계, "새 배포"는 W-03 — [PR #20](https://github.com/Softbank-Hackathon-2026-Team-Daisy/daisy/pull/20)
- 04:59 [앱] 웹 코드보다 보드 결정이 새로우면 보드를 따름: 빌드는 Jenkins, W-12 합계는 A-05 · 호출 기록은 `ai-usage?deployment_id=`, 결과는 "호출 성공 · 호출 실패", 확인 못 한 토큰은 "—" — [PR #20](https://github.com/Softbank-Hackathon-2026-Team-Daisy/daisy/pull/20)
- 04:59 [앱] 서버 · 인프라 미정 항목은 `ios/SPEC.md` §6-9 한 곳에 모으고, 결정 전까지 앱 가정으로 동작 — [PR #20](https://github.com/Softbank-Hackathon-2026-Team-Daisy/daisy/pull/20)
- 10:42 [CI] CI/CD에 해당하는 일은 전부 인프라팀 담당 (Terraform 실행 위치 · 생성기 범위 논의 결과, 김승환 공유) — [슬랙](https://softbankhackathon2026.slack.com/archives/C0C1YSY25LZ/p1790818940410619?thread_ts=1790771233.456579&cid=C0C1YSY25LZ)

### 10/1 (목) 오후

- 12:11 [웹] 상태를 바꾸는 요청(시작 · 다시 시도 · 승인 · 롤백)은 버튼 한 번에 요청 하나 · `Idempotency-Key` 하나, 누르는 동안 버튼 비활성 — [커밋](https://github.com/Softbank-Hackathon-2026-Team-Daisy/daisy/commit/f480397)
- 12:11 [웹] 폴링 간격 5초는 `POLL_MS` 한 곳에서 관리, 끝난 빌드 · 배포는 폴링을 멈춤 — [커밋](https://github.com/Softbank-Hackathon-2026-Team-Daisy/daisy/commit/f480397)
- 12:11 [웹] 403은 공통 문구 하나(`errorMessage()`)로, viewer는 시작 · 다시 시도 · 승인 · 롤백 버튼 비활성 — [커밋](https://github.com/Softbank-Hackathon-2026-Team-Daisy/daisy/commit/f480397)
- 12:59 [CI] Jenkins 화면은 배포 키가 있어 외부에 공개하지 않음(앱 "Jenkins 로그 열기" 버튼 숨김), 단계 · 로그 · 결과는 서버가 Jenkins REST API(API 토큰 인증)로 받아 전달 — [PR #17](https://github.com/Softbank-Hackathon-2026-Team-Daisy/daisy/pull/17#issuecomment-5924457327)
- 12:59 [인프라] 헬스체크는 한 번만: URL · 상태 코드 · 응답 시간 1회 측정값(ms)까지 제공, p95는 없음 — [PR #17](https://github.com/Softbank-Hackathon-2026-Team-Daisy/daisy/pull/17#issuecomment-5924457327)
- 12:59 [인프라] AWS 배포는 새 컨테이너가 헬스체크를 통과해야 트래픽을 옮기고, 실패하면 이전 컨테이너가 계속 서비스 · CD 결과는 실패 — [PR #17](https://github.com/Softbank-Hackathon-2026-Team-Daisy/daisy/pull/17#issuecomment-5924457327)
- 13:02 [웹] 배포 전체 `running` 문구는 "진행 중"(환경별 `applying`의 "배포 중"과 구분) — [PR #20 리뷰](https://github.com/Softbank-Hackathon-2026-Team-Daisy/daisy/pull/20#pullrequestreview-5374842999) · [PR #23](https://github.com/Softbank-Hackathon-2026-Team-Daisy/daisy/pull/23)
- 13:02 [CI] Jenkins에 "Pipeline: REST API" 플러그인을 넣어 서버가 단계별 상태 · 승인 대기(`wfapi`)를 조회 (16:11 PR #17 머지) — [커밋](https://github.com/Softbank-Hackathon-2026-Team-Daisy/daisy/commit/bc5af20) · [PR #17](https://github.com/Softbank-Hackathon-2026-Team-Daisy/daisy/pull/17)
- 13:19 [CI] CD를 `daisy-cd-plan`(plan · 위험 검사 · 요약)과 `daisy-cd-apply`(승인한 plan 적용 · 헬스체크) 두 Job으로 분리, 서버가 승인 뒤 `daisy-cd-apply`를 `PLAN_BUILD` · `APPROVAL_ID`로 시작 — [커밋](https://github.com/Softbank-Hackathon-2026-Team-Daisy/daisy/commit/ab5d222)
- 13:26 [CI] Jenkins 실행 결과는 콜백이 아니라 서버가 Jenkins 상태 · 로그를 조회하는 폴링으로 받음 (서버 질문에 인프라 황지환 답, 임채준과 합의 · 조회 주기는 협의 중) — [PR #19](https://github.com/Softbank-Hackathon-2026-Team-Daisy/daisy/pull/19#issuecomment-5924727810)
- 13:26 [서버] Jenkins 요청 응답이 유실돼도 같은 apply를 자동 재실행하지 않고, 중단 요청 수락 · 타임아웃만으로 종료 판단 · 잠금 해제하지 않음(불명확하면 `unknown` 유지), 서버 `target_lock`과 Terraform 잠금을 함께 사용 (서버 설계 · 인프라 동의) — [PR #19](https://github.com/Softbank-Hackathon-2026-Team-Daisy/daisy/pull/19#issuecomment-5924727810)
- 13:26 [앱] 끝난 배포 · 빌드는 폴링을 멈추고(웹과 같게), 헬스는 1회 측정값으로 "200 OK · 120ms" 표기 — [PR #24](https://github.com/Softbank-Hackathon-2026-Team-Daisy/daisy/pull/24)
- 13:49 [웹] 웹도 앱과 같게 W-03 "Jenkins 로그 열기" 버튼 제거, CI 단계 이름 `Checkout → Test → Build & Push → Trigger CD`, 헬스 형식 "200 OK · 120ms"로 맞춤 — [PR #24 리뷰](https://github.com/Softbank-Hackathon-2026-Team-Daisy/daisy/pull/24#pullrequestreview-5375097728)
- 14:22 [인프라] AWS 네트워크(VPC `10.20.0.0/16` · 서브넷 · IGW)는 `infra/bootstrap/aws-network`로 한 번 만들어 유지하고, 앱 모듈은 `vpc_id` · `public_subnet_ids` · `private_subnet_ids`를 받아 보안 그룹 · ALB · ECS만 다룸 (모듈 입력 변수 변경, 김승환에게 공유) — [커밋](https://github.com/Softbank-Hackathon-2026-Team-Daisy/daisy/commit/2c9ba81) · [PR #26](https://github.com/Softbank-Hackathon-2026-Team-Daisy/daisy/pull/26)
- 14:22 [인프라] 팀 계정이 없어 개인 AWS 계정을 실제 환경으로 씀(비용 정산 예정, 생성 권한 · `PLAN_ONLY` 해제는 사람이 확인), 9/30 "개인 계정은 plan까지만" 대체 — [커밋](https://github.com/Softbank-Hackathon-2026-Team-Daisy/daisy/commit/2c9ba81) · [PR #26](https://github.com/Softbank-Hackathon-2026-Team-Daisy/daisy/pull/26)
- 15:35 [인프라] AI Terraform 생성은 `infra/ai/` 코드를 Jenkins `daisy-cd-plan`이 실행: `claude-opus-5-5` + 구조화 출력(파일 3개) + 프롬프트 캐시, 재사용 여부는 입력 지문(vars.json · 기준 모듈 · 규칙) 비교로 판단, AI 시도는 환경당 총 3번 — [커밋](https://github.com/Softbank-Hackathon-2026-Team-Daisy/daisy/commit/f475ae6d99f80d50742e36536f20eb22d305848b)
- 16:16 [인프라] 서버 `ai_usage` · 승인 화면용 값은 `plan-summary.json`의 환경별 `ai`(`mode` · `ai_calls` · `usage_total` · 실패 메시지)로 제공, AI는 apply하지 않고 삭제 plan에는 AI를 부르지 않음, `USE_AI=false`면 기준 모듈 그대로(N-02 대안) — [PR #27](https://github.com/Softbank-Hackathon-2026-Team-Daisy/daisy/pull/27)
- 16:27 [앱] iPhone 아래 탭은 시스템 탭 대신 얇은 글래스 캡슐 바(높이 44, SF Symbols만 · 글씨 없음): 일곱 메뉴를 한 줄에(시스템 "더 보기" 없음), 선택 알약은 사이드바와 같은 스프링, 승인 대기는 "배포" 아이콘의 점 — [커밋](https://github.com/Softbank-Hackathon-2026-Team-Daisy/daisy/commit/0ef543f) · [PR #29](https://github.com/Softbank-Hackathon-2026-Team-Daisy/daisy/pull/29)
- 16:38 [CI] 러너의 Jenkins · Docker · terraform 패키지는 `apt-mark hold`로 고정(다시 설치할 때 Jenkins 재시작으로 apply가 끊기지 않게) — [PR #28](https://github.com/Softbank-Hackathon-2026-Team-Daisy/daisy/pull/28)
- 16:38 [인프라] `daisy-cd-plan`의 `USE_AI` 기본값은 `true`, API 장애 · 비용 문제 때 `false`로 기준 모듈 대안 경로 — [PR #28](https://github.com/Softbank-Hackathon-2026-Team-Daisy/daisy/pull/28)
- 16:59 [앱] 페이지 · 흐름 화면 머리줄은 반투명(`.ultraThinMaterial`)이라 내용이 뒤로 스크롤되고, iPhone은 스크롤 끝이 탭 바 위 40pt 여백까지 내려감 — [커밋](https://github.com/Softbank-Hackathon-2026-Team-Daisy/daisy/commit/ac6fd6d) · [PR #29](https://github.com/Softbank-Hackathon-2026-Team-Daisy/daisy/pull/29)
- 17:23 [CI] apply 중 중단은 지원하지 않음: 서버는 apply 중 강제 중단을 호출하지 않고 "중단 요청됨"으로 보이며 apply 결과를 기다림 (임채준 16:34 안 · 김승환 17:23 수락) — [PR #17](https://github.com/Softbank-Hackathon-2026-Team-Daisy/daisy/pull/17#issuecomment-5927625836)
- 17:27 [인프라] 온프레미스 기준 모듈 입력은 AWS와 같은 공통 `image` · `image_tag`(커밋 해시, CI는 40자) · `port`, Docker SSH 주소 · VM 바인딩 IP · 게시 포트는 외부 입력, `service_url`은 내부망 HTTP 주소(외부 HTTPS는 별도 작업) — [PR #31](https://github.com/Softbank-Hackathon-2026-Team-Daisy/daisy/pull/31)
- 18:53 [샘플] `sample-monolith` v1.1.0: 화면과 `/version`(`platform` 필드 추가, 기존 필드 유지)에 실행 환경 표시 — 런타임이 넣는 값으로 `AWS · ECS Fargate` · `GCP · Cloud Run` · `On-premises · Docker` · `Local` 판별, `DEPLOY_PLATFORM`이 있으면 그 값, Terraform 변경 없음 (샘플 담당 박승준 허락 · 임채준 머지) — [sample-monolith PR #2](https://github.com/Softbank-Hackathon-2026-Team-Daisy/sample-monolith/pull/2)
- 18:58 [팀] ADR-007 확정: 앱도 웹과 같은 전체 흐름(W-00 ~ W-14, 같은 API), 문구는 웹에서 가져오고 색 · 모양 · 레이아웃은 앱 디자인, 푸시 알림은 앱만 (팀장 결정, 노션 ADR 갱신은 따로) — [PR #33](https://github.com/Softbank-Hackathon-2026-Team-Daisy/daisy/pull/33) · [커밋](https://github.com/Softbank-Hackathon-2026-Team-Daisy/daisy/commit/6dd073b932ab9c3a3312baf5102f2e70546ce563)
- 19:24 [서버] 계정 역할은 `owner`(승인 · 변경) · `viewer`(조회만) 둘, `ai_usage.attempt`는 개별 호출 수가 아니라 생성 · 수정 회차(1–3), 전체 삭제(`destroy`) 배포 종류는 이번에 넣지 않음 (김승환 18:28 리뷰 · 하은현 반영, 19:41 #19 브랜치로 머지) — [PR #32](https://github.com/Softbank-Hackathon-2026-Team-Daisy/daisy/pull/32#issuecomment-5929461042)
- 19:39 [서버] 백엔드 역할 재분담: 하은현은 인증 · 인가, 프로젝트 · 저장소 · 대상 환경 · 빌드 이력, 공개 REST · 조회 API · OpenAPI, AI 사용량 · 비용 합계 응답 / 김승환은 배포 접수 · 상태 전이 · 승인 · 취소 · 재시도 · 롤백 실행 규칙, Jenkins 실행 요청 · 추적 · 결과 수신, 멱등성 · 락 · 장애 복구, 이벤트 저장 · SSE 기반, 스크립트 · AI 사용량 수신 / 서버는 Terraform을 돌리지 않고 plan · apply 실행과 산출물은 인프라 (김승환 리뷰 · 팀장 김도영 반영, PR #33 머지 전) — [PR #33 리뷰](https://github.com/Softbank-Hackathon-2026-Team-Daisy/daisy/pull/33#pullrequestreview-5378051561) · [커밋](https://github.com/Softbank-Hackathon-2026-Team-Daisy/daisy/commit/5e18e3e220aca86a9caf40322f7fc8997ff3a707)
- 19:39 [서버] 계약 담당: REST · OpenAPI는 하은현, SSE 이벤트 · 배포 상태 이름은 하은현 · 김승환 공동, Jenkins Job API · `plan-summary.json`을 받는 쪽은 김승환, plan 상세 · Terraform 파일은 인프라가 만들고 서버가 받아 보관 · 조회 (`deploy.yaml` 파싱 · 검증 주체는 아직 미정) — [PR #33 리뷰](https://github.com/Softbank-Hackathon-2026-Team-Daisy/daisy/pull/33#pullrequestreview-5378051561) · [커밋](https://github.com/Softbank-Hackathon-2026-Team-Daisy/daisy/commit/5e18e3e220aca86a9caf40322f7fc8997ff3a707)
- 19:39 [CI] `sample-monolith`의 GitHub Actions(→ GHCR)는 끄지 않고 백업으로 두고, 데모 이미지는 Jenkins `daisy-ci`로 (임채준 질문 · 김도영 결정) — [PR #33](https://github.com/Softbank-Hackathon-2026-Team-Daisy/daisy/pull/33#issuecomment-5929710835) · [커밋](https://github.com/Softbank-Hackathon-2026-Team-Daisy/daisy/commit/5e18e3e220aca86a9caf40322f7fc8997ff3a707)
- 19:40 [서버] `ai_usage`는 실제 호출 1건당 1행: 합계(`usage_total`)만으로 가짜 호출 행을 만들지 않고, 상세를 못 받으면 0원이 아니라 미확인(비용 NULL)으로 / 내부 작업 `prepare`는 이름을 유지하고 Jenkins `daisy-cd-plan`에 매핑 / plan 중단(stop)은 인프라 동작 확인 뒤 켬 (하은현 질문에 김승환 답, 19:41 PR #32 머지) — [PR #32](https://github.com/Softbank-Hackathon-2026-Team-Daisy/daisy/pull/32#issuecomment-5929687286) · [이슈 #35](https://github.com/Softbank-Hackathon-2026-Team-Daisy/daisy/issues/35)
- 19:41 [웹] W-03 `Trigger CD`는 운영에서 늘 실행되지 않아(Jenkins `NOT_EXECUTED`) "건너뜀"으로 표시, CD 단계 이름은 `daisy-cd-plan`: Prepare → Infra code → Plan → Summary · `daisy-cd-apply`: Verify → Apply → Health check (임채준 리뷰 · 김도영 반영, 서버가 넘길 값 이름 `skipped`는 하은현과 확인 중) — [PR #25 리뷰](https://github.com/Softbank-Hackathon-2026-Team-Daisy/daisy/pull/25#pullrequestreview-5378065678) · [커밋](https://github.com/Softbank-Hackathon-2026-Team-Daisy/daisy/commit/be857d6)
- 20:21 [서버] 서버 공통 기반 머지: ERD 17개 테이블 · V1 Flyway · 공통 오류 응답 · `X-Request-ID` 추적, 서버 Postgres는 작업 큐가 아니라 Jenkins 명령 제출 · 폴링 · 장애 복구 기록(`jenkins_execution`)이고 인스턴스 수만으로 Redis로 바꾸지 않음 (하은현 승인 · 김승환 머지) — [PR #19](https://github.com/Softbank-Hackathon-2026-Team-Daisy/daisy/pull/19) · [커밋](https://github.com/Softbank-Hackathon-2026-Team-Daisy/daisy/commit/682e6be938a6930a27d4cc96a99b7da0b2bf487f)
- 20:21 [서버] 내부 데이터 표현: 같은 커밋 재빌드도 `source_version` ID를 따로, 이미지는 서비스별 `image_refs` map, 배포 `kind`는 normal · retry · rollback, `attempt`는 생성 전 0 → 1–3 (API로 어떻게 내보낼지는 소비자와 따로 맞춤) — [PR #19](https://github.com/Softbank-Hackathon-2026-Team-Daisy/daisy/pull/19) · [커밋](https://github.com/Softbank-Hackathon-2026-Team-Daisy/daisy/commit/682e6be938a6930a27d4cc96a99b7da0b2bf487f)
- 21:38 [팀] 서비스 이름은 **Unibloom** (10/1 회의, 황지환 안 "한 번 정의하고, 어디서든 피우다"), 팀 이름은 Team Daisy 그대로 — [슬랙](https://softbankhackathon2026.slack.com/archives/C0C1YSY25LZ/p1790858284059339) · [슬랙](https://softbankhackathon2026.slack.com/archives/C0C1YSY25LZ/p1790858378166849)
- 21:38 [CI] GitHub 레포 이름 `daisy` → `unibloom` (옛 주소는 자동 이동, 로컬은 `git remote set-url`로 바꾸기), 인프라는 Jenkins Job 저장소 주소 · webhook도 새 주소로 — [슬랙](https://softbankhackathon2026.slack.com/archives/C0C1YSY25LZ/p1790858284059339)
- 21:38 [앱] 다음 Mac 릴리스부터 `Unibloom.dmg`로 올리고 웹 W-14가 맞춤, 앱 표시 이름은 Figma(unibloom) 기준 — [슬랙](https://softbankhackathon2026.slack.com/archives/C0C1YSY25LZ/p1790858284059339)
- 21:38 [팀] 서버 · 인프라 · 앱 문서 안 `daisy` 표기는 각 영역이 정리 — [슬랙](https://softbankhackathon2026.slack.com/archives/C0C1YSY25LZ/p1790858284059339)
- 21:41 [인프라] 도메인은 `unibloom.cloud` (`unibloom.com`은 못 씀, 김도영 제안 · 황지환 진행, 21:52 구매 완료 · 설정 진행 중) — [슬랙](https://softbankhackathon2026.slack.com/archives/C0C1YSY25LZ/p1790858359800119?thread_ts=1790858359.800119&cid=C0C1YSY25LZ) · [슬랙](https://softbankhackathon2026.slack.com/archives/C0C1YSY25LZ/p1790859158930959)
- 21:46 [서버] 조회 API 모양(하은현 #38 제안 · 웹 김도영 수락, 머지 전): 빌드 상태에 `queued` 추가(시작 전, 화면 "대기 중"), 목록은 `{ items, next_cursor }` 봉투(A-02 포함), A-02 `current`는 배포가 없으면 통째로 null · 값이 없으면 "—", A-06 커밋 메시지 · 작성자 · 시각은 미제공, 역할은 `owner` · `viewer` — [PR #38](https://github.com/Softbank-Hackathon-2026-Team-Daisy/unibloom/pull/38#issuecomment-5931767944)
- 21:55 [팀] 결정 보드를 레포 루트 `BOARD.md`로 옮겨 팀 공용으로 (`ios/BOARD.md`에서 승격, 루트 `AGENTS.md` §12-9에 위치 기록) — [PR #39](https://github.com/Softbank-Hackathon-2026-Team-Daisy/unibloom/pull/39)
- 21:55 [앱] Mac은 화면 위 머리줄의 재질 띠를 없애 내비게이션 바가 보이지 않게 (iPhone은 반투명 유지), 앱 이름 · 워드마크 · DMG를 Unibloom으로 (번들 ID · 모듈 이름은 그대로) — [PR #39](https://github.com/Softbank-Hackathon-2026-Team-Daisy/unibloom/pull/39)
