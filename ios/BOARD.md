# Team Daisy 결정 보드

슬랙 · 노션 · 깃에서 **팀이 결정한 것만** 시간순으로 모아요. 파트 구분 없이 한 줄씩 적고, 30분마다 전담 에이전트가 갱신해요.

## 작성 지침

1. **결정만 적어요.** 회의 합의, 담당 파트의 확정(결정 기록 · 머지된 PR · "확정"/"넣을게요" 같은 명시적 답)만요. 제안 · 질문 · 진행 상황 · 아무도 받지 않은 `(가칭)`은 적지 않아요.
2. **출처가 있어야 해요.** 줄마다 슬랙 · 노션 · 깃 링크를 달아요. 링크가 없으면 적지 않아요.
3. **미정이 정해지면 미정을 남기지 않아요.** 정해진 시각의 칸에 결정으로 적고, 보드 어디에도 미정으로 남기지 않아요.
4. **번복은 지우지 않아요.** 이전 줄은 ~~취소선~~ + `→ 번복: 날짜 칸`으로 두고, 새 결정은 그 시각의 칸에 새로 적어요.
5. **시간 기준은 KST예요.** 날짜별 오전(00:00–11:59) · 오후(12:00–23:59) 칸으로 묶고, 결정이 난 시각(메시지 · 회의 · 머지)으로 넣어요.
6. **한 줄 형식:** `- HH:MM [파트] 결정 — [출처](링크)`. 파트: 팀 · 웹 · 앱 · 서버 · 인프라 · CI · 샘플.
7. **비밀값 · 개인 연락처는 적지 않아요.**

상태: 마지막 갱신 2026-09-30 20:35 KST · 확인한 범위 Slack ~20:35 / Notion ~20:35 / GitHub ~20:35

## 결정 기록

### 9/28 (월) 오후

- 21:37 [팀] 팀장은 김도영 — [노션](https://app.notion.com/p/3e98bee9ada4804ab1a2e9817314047e)
- 21:37 [팀] 예선 전까지 매일 21:00–22:00 온라인 정기 회의(Slack 허들), 문서는 Notion · 소통은 Slack — [노션](https://app.notion.com/p/3e98bee9ada4804ab1a2e9817314047e)
- 21:37 [팀] 역할: 웹 FE 김도영·박승준 / 웹 BE 하은현·김승환 / 인프라 온프레미스 황지환 · 클라우드 임채준 (ADR-001) — [노션](https://app.notion.com/p/3e98bee9ada4804ab1a2e9817314047e)

### 9/29 (화) 오전

- 03:12 [팀] 주제: AI 기반 온프레미스·퍼블릭 클라우드 원터치 배포 시스템 (ADR-002) — [노션](https://app.notion.com/p/fe08bee9ada482d2901281a1d7c15c13)
- 03:12 [인프라] IaC는 Terraform (ADR-003) — [노션](https://app.notion.com/p/fe08bee9ada482d2901281a1d7c15c13)
- 03:12 [CI] 앱 입력은 GitHub 저장소 + main merge → GitHub Actions 빌드, 이미지 태그는 커밋 해시 (ADR-004) — [노션](https://app.notion.com/p/fe08bee9ada482d2901281a1d7c15c13)
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
- 20:44 [서버] 작업 큐는 Postgres(`FOR UPDATE SKIP LOCKED`), 인스턴스 2대 이상이면 Redis로 — [PR #6](https://github.com/Softbank-Hackathon-2026-Team-Daisy/daisy/pull/6)
- 20:44 [서버] `terraform apply` 실행·상태·락·SSE는 하은현, 생성·검증·공통 Terraform CLI 실행부는 김승환 — [PR #6](https://github.com/Softbank-Hackathon-2026-Team-Daisy/daisy/pull/6)
- 20:44 [서버] 한 환경이 3회 실패해도 나머지 환경은 계속 진행 (Q7) — [PR #6](https://github.com/Softbank-Hackathon-2026-Team-Daisy/daisy/pull/6)
- 20:44 [서버] plan이 stale되면 다시 plan → 재승인, 이때 `attempt`는 올리지 않음 — [PR #6](https://github.com/Softbank-Hackathon-2026-Team-Daisy/daisy/pull/6)
- 20:44 [서버] 락은 같은 Terraform state를 쓰는 대상 기준, 승인 접수 시점부터 — [PR #6](https://github.com/Softbank-Hackathon-2026-Team-Daisy/daisy/pull/6)
- 20:44 [서버] 취소는 apply 전까지, 이후는 중단 요청 — [PR #6](https://github.com/Softbank-Hackathon-2026-Team-Daisy/daisy/pull/6)
- 20:44 [서버] JSON은 전역 `snake_case` — [PR #6](https://github.com/Softbank-Hackathon-2026-Team-Daisy/daisy/pull/6)
- 20:44 [서버] AI 비용은 USD를 배포 단위로 합산 → 고정 환율로 원화 환산, "추정" + 적용 환율 표시, 확인 못 한 비용은 NULL — [PR #6](https://github.com/Softbank-Hackathon-2026-Team-Daisy/daisy/pull/6)
- 21:00 [팀] 에이전트 개발 방식: `daisy` 모노레포 하나, 파트 `AGENTS.md`, `SPEC.md` 먼저 → 구현 → SPEC 최신화 → PR — [노션](https://app.notion.com/p/3e98bee9ada480d68a41e6de6155225e)
- 21:00 [팀] 자기 영역은 자율 결정 후 Slack 공유, 다른 파트 수정은 직접 하지 않고 이슈·Slack으로 요청 — [노션](https://app.notion.com/p/3e98bee9ada480d68a41e6de6155225e)
- 21:00 [샘플] `sample-msa`는 프론트 컨테이너 1 + 백엔드 컨테이너 1, 박승준 담당 — [노션](https://app.notion.com/p/3e98bee9ada480d68a41e6de6155225e)
- 21:00 [서버] 도메인을 구매해서 HTTPS 적용 (하은현·김승환, 9/30 오후 전) — [노션](https://app.notion.com/p/3e98bee9ada480d68a41e6de6155225e)
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
- 17:44 [서버] plan 상세(환경별 리소스 · 변경 동작)와 생성된 Terraform 파일 조회 산출물은 김승환이 제공, API 연결은 하은현과 — [PR #9](https://github.com/Softbank-Hackathon-2026-Team-Daisy/daisy/pull/9#issuecomment-5907560258)
- 17:57 [앱] TestFlight 앱 이름 "Daisy Deploy"(홈 화면 이름은 Daisy), 빌드 번호는 `yyMMddHHmm` — [PR #8](https://github.com/Softbank-Hackathon-2026-Team-Daisy/daisy/pull/8)
- 18:09 [앱] TestFlight 그룹: 내부 `Team Daisy`(자동 배포), 외부 `Public Link`(베타 심사 후 공개) — [PR #8](https://github.com/Softbank-Hackathon-2026-Team-Daisy/daisy/pull/8)
- 18:55 [앱] Mac 직접 다운로드는 공증된 DMG를 `daisy` GitHub Releases(태그 `mac-v<버전>-<빌드>`, pre-release)에 올리고 웹 W-14가 연결 (웹 18:57 수락) — [PR #9](https://github.com/Softbank-Hackathon-2026-Team-Daisy/daisy/pull/9#issuecomment-5908805197)
- 19:46 [인프라] 개인 AWS 계정은 plan까지만(`ReadOnlyAccess` · Jenkins `PLAN_ONLY=1` · Zero spend budget), apply는 팀 계정에서 — [커밋](https://github.com/Softbank-Hackathon-2026-Team-Daisy/daisy/commit/de0e61f7ae6e3054656271bc75f19846f89a25da)
- 20:25 [앱] 오프라인 예시 데이터 모드 추가: 로그인의 "예시 데이터로 둘러보기 (오프라인)", 화면마다 "예시 데이터" 배지, 읽기 전용, 실서버 데이터와 섞지 않음 (실서버가 기본) — [커밋](https://github.com/Softbank-Hackathon-2026-Team-Daisy/daisy/commit/beb95e6)
- 20:31 [팀] 루트 규칙은 영어 `AGENTS.md`(`CLAUDE.md` 대체), 결정 권한 4단계: 파트 안은 바로 확정 · 제공하는 계약은 결정 후 소비자에게 이슈 · 다른 파트는 담당자가 결정(요청은 `(가칭)` + 이슈) · 팀 사항은 `[결정]` 이슈 + 회의 — [PR #2](https://github.com/Softbank-Hackathon-2026-Team-Daisy/daisy/pull/2)
- 20:31 [팀] 다른 파트 변경은 PR이 아니라 이슈로 요청, 구현 전에 모순 확인 — [PR #2](https://github.com/Softbank-Hackathon-2026-Team-Daisy/daisy/pull/2)
- 20:32 [앱] 웹 W-14 Mac 다운로드는 고정 주소 `releases/download/mac-latest/Daisy.dmg`, 새 빌드는 파일만 교체 — [PR #9](https://github.com/Softbank-Hackathon-2026-Team-Daisy/daisy/pull/9#issuecomment-5910304737)
