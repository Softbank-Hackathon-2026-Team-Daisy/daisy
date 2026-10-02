# SPEC.md — Unibloom 웹 대시보드 명세와 백엔드 요구사항

> 작성: 김도영 · 상태: **초안 (9/30)** · 참조: 루트 `AGENTS.md`, 노션 ADR-002·004·006·007, 플로우차트 설계서, `ios/SPEC.md`, `server/AGENTS.md`
> 화면은 Figma [와이어프레임 v1.0](https://www.figma.com/design/5nqU4xotMh5jcsaDqOcTST/Team-Daisy-%EC%98%88%EC%84%A0?node-id=0-1) (9/30 확정), 모양은 같은 파일의 [디자인 시스템](https://www.figma.com/design/5nqU4xotMh5jcsaDqOcTST/Team-Daisy-%EC%98%88%EC%84%A0?node-id=2-4)을 따라요.
>
> **백엔드 파트(하은현, 김승환)는 [§6 백엔드 요구사항](#6-백엔드-요구사항)부터 읽으면 돼요.** 앱과 같이 쓰는 API는 `ios/SPEC.md` §6의 ID를 그대로 쓰고, 웹 때문에 새로 필요한 것만 `WR-xx` 🆕로 적었어요.

> ⚠️ **ID 표기:** 이 문서에서 `W-00`~`W-14`는 **웹 화면 ID**(와이어프레임)예요. `ios/SPEC.md`의 승인 API `W-01`과 겹쳐서, 이 문서에서는 API를 항상 **"API W-01"**로 적어요.

---

## 1. 무엇을 만드나요

**배포 흐름 전체를 처음부터 끝까지 돌리는 웹 대시보드**예요 (ADR-007, 10/1부터 앱도 같은 범위). 저장소를 연결하고, 환경을 고르고, AI가 만든 plan을 확인·승인하고, 병렬 배포를 지켜보고, 모든 환경이 같은 이미지로 떴는지 확인해요.

| 질문 | 웹이 답하는 화면 |
|---|---|
| 어떻게 들어가지? | W-00 로그인 |
| 지금 어느 환경에 어떤 버전이 떠 있지? 다음에 할 일은? | W-01 개요 |
| 이 저장소를 배포하려면? | W-02 연결 → W-03 이미지 빌드 → W-04 환경 선택 |
| AI가 만든 Terraform은 통과했어? 몇 번 고쳤어? | W-05 생성 · 검증 (한 환경 실패 시 W-05b) |
| 무엇이 바뀌는지 보고 승인하려면? | W-06 승인 |
| 배포가 어디까지 갔어? 모두 같은 이미지로 떴어? | W-07 배포 중 → W-08 결과 |
| 언제 무엇을 어디에 배포했지? 되돌리려면? | W-09 이력 · 롤백 |
| 환경 · 검증된 스크립트 · AI 사용량 · 설정은? | W-10 ~ W-13 |

### 1-1. 앱과의 역할 분리

웹과 앱은 코드를 공유하지 않고 **같은 백엔드 API만** 써요.

**10/1 확정: 앱도 웹과 같은 전체 흐름을 해요** (팀장 결정, 루트 `AGENTS.md` §12-4 ADR-007, #33). 웹 화면 · 일정은 그대로예요.

- **웹과 앱이 같이 하는 것:** W-00 ~ W-14 전부 — 저장소 연결, 환경 선택, 배포 시작, plan 확인 · 승인 · 거절, 진행 · 결과 · 이력 · 롤백, 환경 · 스크립트 · AI 사용량 · 설정. 두 쪽이 같은 API(공용 · `WR-xx`)를 써요
- **나누는 기준:** 앱은 문구(화면 · 메뉴 이름, 상태 이름, 안내 문구)를 웹에서 가져가고, 색 · 모양 · 레이아웃은 앱 디자인을 따라요 (`ios/AGENTS.md`, 9/30 승준 님). 웹에서 문구를 바꾸면 앱에도 알려요
- **앱만 하는 것:** 푸시 알림(APNs, 그전에는 로컬 알림). 웹은 브라우저 알림
- 웹은 **GitHub, 클라우드, Terraform에 직접 붙지 않아요.** 모든 데이터는 Unibloom 백엔드 API를 거쳐요

### 1-2. 데모 목표

- 발표에서 **웹으로 전체 흐름을 한 번에** 보여줘요: W-01 → W-02 → L-01 → W-03 → W-04 → L-02 → W-05 → W-06 → L-03 → W-07 → W-08
- 핵심 데모 포인트 두 가지
  - **이식성:** W-08의 동일성 검증 표(이미지 digest 비교) "3/3 일치"
  - **AI 활용:** W-05의 "시도 n/3", W-11의 재사용 · 폐기 이력, W-12의 "AI 호출 0회" 환경
  - **안전한 복구:** W-09 롤백 (운영진이 킥오프 Q&A에서 "좋은 평가 요소"라고 답함)
- 승인은 웹(W-06)과 앱 어느 쪽에서도 할 수 있어요. 발표에서는 앱 승인을 보여줄 수도 있어요 (`ios/SPEC.md` §1-3)

---

## 2. 화면 구성

와이어프레임은 1440px 기준이에요. 흐름은 이래요.

```
W-00 로그인 → W-01 개요 → W-02 저장소 연결 → L-01 → W-03 이미지 빌드 → W-04 환경 선택
→ L-02 → W-05 생성 · 검증 (W-05b 한 환경 중단) → W-06 승인 → L-03 → W-07 병렬 배포 → W-08 결과 → W-09 이력
메뉴 화면: W-10 환경 · W-11 스크립트 · W-12 AI 사용량 · W-13 설정 · W-14 Mac 앱 다운로드 (Dialog)
```

### 2-1. 흐름 화면

| ID | 화면 | 내용 | 우선 |
|---|---|---|---|
| W-00 | **로그인** | 아이디 · 비밀번호로 Bearer 토큰 발급(R-02). "데모 계정으로 둘러보기"(viewer, R-03). 왼쪽은 인프라 블록(Stack 3) + 슬로건. 로그인 버튼은 Secondary. 사이드바 없음. GitHub 로그인은 넣지 않아요 | M |
| W-00b | 로그인 · 실패 | 401 → 상단 오류 알림 + 비밀번호 칸 Error, 아이디는 두고 비밀번호만 비움. 네트워크 오류 → "서버에 연결하지 못했어요. 잠시 후 다시 시도해 주세요." 세션 만료로 돌아오면 Info "다시 로그인해 주세요." | M |
| W-01 | **개요** | 환경별 현재 버전(커밋 · 배포 시각 · 공개 URL · 헬스), "3/3 일치" 이식성 표시, 지금 할 일(승인 대기 → W-06, Secondary 버튼), 최근 실행 | M |
| W-02 | **애플리케이션 연결** (STEP 1) | 저장소 URL, 배포 기준 브랜치, `deploy.yaml` 확인. 입력은 GitHub 저장소 연결 하나 (ADR-004). 데모 앱 sample-monolith 기준 (포트 8080, `/health`, DB 없음) | M |
| ~~W-02b~~ | ~~연결 · 업로드~~ | **범위 제외 (9/30).** 소스 업로드 API가 빠졌어요. 와이어프레임에는 기록용으로 흐리게 남아 있고, 구현하지 않아요 | — |
| W-03 | **이미지 빌드** (STEP 2) | main merge 감지, Jenkins 빌드 단계(`Checkout → Test → Build & Push → Trigger CD`, Trigger CD는 운영에서 늘 "건너뜀"), 이미지 태그(커밋 해시). Jenkins 화면은 외부 비공개라 로그 링크 없음 (#17) | M |
| W-04 | **배포할 환경 선택** (STEP 3) | 여러 환경 동시 선택, 카드에 재사용 / 새로 생성 미리 표시, 선택 요약 | M |
| W-05 | **인프라 코드 생성 · 검증** (STEP 4) | 환경별 진행과 "시도 n/3", 검증 단계, 생성된 스크립트 보기. SSE로 실시간 갱신 | M |
| W-05b | **AWS만 멈췄어요** | 한 환경이 3번 모두 실패하면 그 환경만 멈추고(`failed`) 나머지는 계속 진행해요. 시도 기록과 환경별 상태. "빼고 계속" 버튼 없음 | M |
| W-06 | **변경 사항 확인 후 승인** (STEP 5) | 환경별 요약(+생성 ~변경 −삭제, 위험 설정), 환경별 plan 상세, AI 비용(추정). **노란 48px "승인하고 배포"가 화면에서 가장 큰 요소** | M |
| W-07 | **배포 중** (STEP 5) | 환경 3개 레인으로 `terraform apply` 병렬 진행, 로그 뷰어, 연결 상태 | M |
| W-08 | **배포 결과** (STEP 6) | 환경별 결과 카드(URL · 헬스), 동일성 검증 표(성공한 환경끼리 이미지 digest 비교). 일부만 성공하면 "일부 성공" 배지(`partially_succeeded`). TestFlight QR 자리 | M |
| W-09 | **배포 이력 · 롤백** | 버전별 이미지 · 스크립트 · 환경. **롤백** 버튼 → 되돌릴 환경 체크박스 + 확인 Dialog → 롤백 배포 생성 → plan · 승인(W-06) · apply를 그대로 거쳐요. 이력에 새 행이 생겨요 | M |

### 2-2. 전환 로딩

| ID | 구간 | 첫 문구 |
|---|---|---|
| L-01 | W-02 → W-03 | 저장소를 연결하고 있어요 |
| L-02 | W-04 → W-05 | AI가 환경별 인프라 코드를 만들고 있어요 |
| L-03 | W-06 → W-07 | 승인된 plan으로 배포를 준비하고 있어요 |

- 화면 가운데 인프라 블록 애니메이션, 아래에 "잠시만 기다려주세요"와 설명 문구
- 설명 문구는 첫 고정 문구 뒤로 10개를 3.5초마다 돌려요. 목록은 `src/pages/loading/captions.ts` 한 곳에서 관리해요
- 서버가 완료 이벤트(SSE)를 보내면 바로 다음 화면으로 넘어가요. **3초 안에 끝나는 전환에는 쓰지 않아요**
- 애니메이션 규칙은 `AGENTS.md` §5-6

### 2-3. 메뉴 화면

| ID | 화면 | 내용 | 우선 |
|---|---|---|---|
| W-10 | 환경 | 대상 환경 연결 상태와 인프라 구성. "환경 추가"는 범위 결정 필요 (§7) | S |
| W-11 | 스크립트 | 검증된 스크립트 목록(환경 · 버전 · 만든 방식 · 검증 · 재사용 횟수 · 마지막 사용), 폐기된 스크립트도 표시, 스크립트 내용 보기 | S (데모 효과 큼) |
| W-12 | AI 사용량 | **배포를 골라서** 그 배포의 AI 호출 수 · 토큰 · 비용(추정) · 재사용한 환경(AI 호출 0회), 호출 기록 표. 여러 배포 합계는 예선 범위에서 하지 않아요. 차트 없음 | S (데모 효과 큼) |
| W-13 | 설정 | 저장소, `deploy.yaml`(읽기 전용), 비밀값(이름만, 값은 다시 볼 수 없음), 알림, 프로젝트 연결 해제(환경 이름 입력 확인) | S |
| W-14 | Mac 앱 다운로드 (Dialog) | 사이드바 하단 "Mac 앱 받기"와 W-00 폼 아래 링크에서 열어요. 로그인 전 · 데모 계정도 받을 수 있어요. **Mac: GitHub Releases 고정 주소 `releases/download/mac-latest/Daisy.dmg`** (늘 최신 빌드, macOS 15 이상, Developer ID 서명 + 공증 완료라 Gatekeeper 안내 없음 — 9/30 20:32 승준 님). **iPhone: TestFlight 공개 링크** (베타 심사 뒤 열림). 새 빌드가 나와도 웹은 바꿀 게 없어요 | S |

### 2-4. 사이드바 (9/30 결정)

- **프로젝트 단위 메뉴**: 개요 · 배포(승인 대기 배지) · 환경 · 이력 · 스크립트 / 아래쪽 AI 사용량 · 설정
- 상단 헤더를 사이드바로 합쳤어요. 위에서부터 로고, 프로젝트 전환(Project Menu), "새 배포", 메뉴, 환경 목록(상태 점), 실시간 연결 상태, 사용자
- **배포 흐름 화면(W-02~W-08, L-xx)에서는 64px 아이콘 바**, 그 밖에서는 240px
- 활성 메뉴는 `--color-surface-strong` 배경 + 왼쪽 2px ink 막대. 노란색은 쓰지 않아요

M = 예선 데모 필수, S = 선택 (S도 모두 만들었어요, §5)

### 2-6. 화면 경로

경로는 `src/paths.ts` 한 곳에서 관리해요. 링크는 문자열 대신 이 함수로 만들어요.

| 화면 | 경로 |
|---|---|
| W-00 · W-00b 로그인 | `/login` (`?next=` 원래 보려던 화면, `?expired=1` 세션 만료 안내) |
| W-01 개요 | `/projects/:projectId` |
| W-02 저장소 연결 | `/connect` |
| W-03 이미지 빌드 | `/projects/:projectId/deploy/build` |
| W-04 환경 선택 | `/projects/:projectId/deploy/targets?commit=` |
| 사이드바 "배포" | `/projects/:projectId/deployments/current` → 가장 최근 배포의 현재 단계로 이동 |
| W-05 · W-05b 생성 · 검증 | `/projects/:projectId/deployments/:deploymentId/generate` |
| W-06 승인 | `…/deployments/:deploymentId/approve` |
| W-07 배포 중 | `…/deployments/:deploymentId/progress` |
| W-08 결과 | `…/deployments/:deploymentId/result` |
| W-09 ~ W-13 | `/projects/:projectId/history` · `/environments` · `/scripts` · `/ai-usage` · `/settings` |
| W-14 앱 설치 | 경로 없음 — 사이드바 · 로그인 화면에서 여는 Dialog |
| L-01 ~ L-03 | 경로 없음 — W-03 · W-05 · W-07에 들어갈 때 게이트로 보여줘요 (§2-2) |
| 개발용 확인 페이지 | `/dev/tokens` · `/dev/components` · `/dev/primitives` (데모 화면 아님) |

### 2-5. 상태 값 (9/30 서버 확정)

| 구분 | 값 | 화면 표시 (Status Badge) |
|---|---|---|
| 배포 전체 | `queued` · `running` · `awaiting_approval` · `succeeded` · `partially_succeeded` · `failed` · `cancelled` | 대기 중 · **진행 중** · 승인 대기 · 성공 · **일부 성공** · 실패 · 취소됨 |
| 환경별 | `waiting` · `generating` · `validating` · `awaiting_approval` · `applying` · `verifying` · `succeeded` · `failed` · `cancelled` | 대기 중 · 생성 중 · 검증 중 · 승인 대기 · 배포 중 · 확인 중 · 성공 · 실패 · 취소됨 |
| 단계 (`step`) | `generate` · `validate` · `plan` · `risk_check` · `apply` · `health_check` | W-05는 앞 4개, W-07은 `apply` · `health_check` |

- 롤백 전용 상태(`rolling_back`)는 없어요. 롤백은 `kind: "rollback"`인 **새 배포**예요
- **배지 색 (9/30 확정, 와이어프레임 기준)**: 대기 중 · 승인 대기 · 취소됨 = 회색(queued), 진행 중 · 생성 중 · 검증 중 · 배포 중 · 확인 중 = 파랑(running), 일부 성공 = 주황(warning), 성공 = 초록, 실패 = 빨강, 롤백 배포가 성공하면 "롤백됨" = 보라. 매핑은 `src/api/status.ts` 한 곳
- 모르는 값이 오면 회색 "알 수 없음"으로 보여주고 깨지지 않아요

---

## 3. 기술 구성

| 항목 | 선택 | 이유 |
|---|---|---|
| 프레임워크 | **React + Vite SPA** | ADR-006 |
| 언어 | TypeScript | API 타입을 OpenAPI와 맞추기 쉬워요 |
| 런타임 · 패키지 매니저 | **Node 22 LTS** (`.nvmrc`) · **pnpm 9** (`packageManager`로 고정) | LTS로 데모 서버 · CI와 맞춰요. lock 파일은 `pnpm-lock.yaml` 하나만 |
| 스타일 | CSS 변수(디자인 토큰) + 일반 CSS | UI 키트 없이 Figma 토큰을 1:1로 옮겨요 |
| 외부 라이브러리 | **최소**. 막힐 때만 추가하고 이유를 ADR에 기록 | ADR-006 |
| 라우팅 | **`react-router`** | 화면이 14개이고, 앱 푸시 · 공유 링크로 W-06 같은 화면에 바로 들어와야 해요. ADR-006에 기록 (9/30 확정) |
| 네트워크 | `fetch` + `src/api/` 클라이언트 한 곳 | |
| 실시간 | **`fetch` 스트리밍으로 SSE를 직접 파싱** (`Authorization` 헤더 사용) + 연결 실패 시 **5초 폴링** | `EventSource`는 헤더를 못 붙여서 (WR-01, 9/30 확정). 서버 SSE는 D3, 그전까지 폴링 |
| 긴 로그 | 느려지면 TanStack Virtual 추가 | 와이어프레임 W-07 NOTE (ADR-006) |
| 차트 | 쓰지 않아요 | W-12도 숫자 · 표로만 |
| 폰트 | IBM Plex Sans KR · IBM Plex Mono (일본어 화면은 IBM Plex Sans JP) | 디자인 시스템. 일본어는 KR 글꼴의 한자 모양이 섞이지 않게 (#75) |
| 화면 언어 | **한국어 · English · 日本語**, 기본값은 브라우저 언어. 설정 · 로그인 화면에서 바꾸고 이 브라우저에 기억. `src/i18n/`의 `t('원문')` + 사전, 라이브러리 없음. 모든 요청에 `Accept-Language`(ko · en · ja) | 앱(#73)과 같은 방식 · 같은 번역. 서버가 보내는 문장은 받은 그대로 보여줘요 (#74 안 A, #75) |
| 목업 | **허용.** `src/mocks/`에만 두고 `// MOCK:` + 화면 배지. `VITE_USE_MOCK=false`면 **서버에 열린 API만 실서버**(`endpoints.ts`의 `SERVER_READY`), 아직 없는 API는 목업으로 답하고 그 화면에 MOCK 배지 (10/2) | 서버 API가 D2~D3에 나와서, 그전에 화면을 만들어야 해요 (`AGENTS.md` §4) |
| 인증 상태 | 토큰은 **`sessionStorage`**(탭 단위)에 두고, 역할(admin · viewer)은 React context. 앱을 켜면 저장된 토큰으로 `/auth/me`를 다시 불러요 | 새로고침 · 링크로 들어와도 로그인 유지, 탭을 닫으면 사라져요 (10/3 실서비스 점검 #102, SPEC §3-2) |

### 3-1. 폴더 구조

```
web/
├─ AGENTS.md                AI 에이전트 규칙 (이 폴더 전용)
├─ SPEC.md                  이 문서
├─ docs/work-log/           날짜별 작업 로그
├─ .nvmrc                  Node 22 LTS
├─ index.html
├─ package.json
├─ vite.config.ts
└─ src/
   ├─ main.tsx · App.tsx    진입점, 라우팅, 사이드바 레이아웃
   ├─ styles/               tokens.css (라이트 · 다크), base.css
   ├─ components/           디자인 시스템 컴포넌트 (Figma 이름 = 컴포넌트 이름)
   ├─ pages/                화면 단위 폴더
   │  ├─ login/             W-00 · W-00b
   │  ├─ overview/          W-01
   │  ├─ connect/           W-02
   │  ├─ image-build/       W-03 (루트 .gitignore의 build/ 규칙을 피하려고 이 이름)
   │  ├─ targets/           W-04
   │  ├─ generate/          W-05 · W-05b
   │  ├─ approve/           W-06
   │  ├─ deploy/            W-07
   │  ├─ result/            W-08
   │  ├─ history/           W-09 (롤백 포함)
   │  ├─ environments/      W-10
   │  ├─ scripts/           W-11
   │  ├─ ai-usage/          W-12
   │  ├─ settings/          W-13
   │  ├─ app-download/      W-14 (Dialog)
   │  ├─ loading/           L-01 ~ L-03 (TransitionLoader · TransitionGate), captions.ts
   │  ├─ dev/               개발용 확인 페이지
   │  └─ flow.ts            W-05 ~ W-08 단계 · 상태 표시 규칙
   ├─ api/                  types(§6-4와 1:1) · client · realtime(SSE) · endpoints · status · useResource · auth
   ├─ mocks/                MOCK 데이터만 (scenario · api · workspace)
   ├─ utils/format.ts       상대 시간 · 커밋 7자리 · 소요 시간 · 원화
   └─ paths.ts              화면 경로 (§2-6)
```

### 3-2. 데이터 흐름

```
Page ──▶ hook ──▶ api/client ──────────▶ Unibloom 백엔드 (REST)
  ▲        │ ◀── api/realtime (fetch 스트림 → 이벤트, 실패 시 5초 폴링) ◀── Unibloom 백엔드 (SSE)
  └ 상태 ──┘
                (서버가 없을 때만) api/client → mocks/
```

- 화면은 `src/api/`를 거쳐서만 데이터를 받아요. 목업 ↔ 실서버 전환이 화면 코드에 닿지 않아요
- SSE가 끊기면 `Last-Event-ID` 헤더로 다시 붙고, `resync`가 오면 스냅샷(API A-04)을 다시 불러요
- 토큰은 `sessionStorage`(탭을 닫으면 사라짐)에 두고, `401`이 오면 지우고 W-00으로 보내요 (세션 만료 안내). 10/3 전에는 메모리에만 둬서 새로고침하면 로그아웃됐어요 (#102)

---

## 4. 경계: 누가 무엇을 하나요

| 영역 | 웹 (김도영) | 백엔드 (하은현 · 김승환) | 빌드 (Jenkins, 9/30 회의) |
|---|---|---|---|
| 저장소 연결 | 입력 · 결과 표시 | 프로젝트 저장, `deploy.yaml` 파싱 · 검증 | — |
| 이미지 빌드 | 진행 표시 | webhook 수신 · 저장 · 조회 API | Jenkins 빌드, 이벤트 전송 |
| 환경 선택 · 배포 시작 | 선택 UI, 배포 생성 요청 | 재사용 / 새로 생성 판단, 작업 큐 | — |
| 생성 · 검증 | 진행 · 스크립트 표시 | AI 생성 · 수정 루프, validate · plan · 위험 검사 | — |
| 승인 | 버튼 · 확인 문구 입력 | 권한 · 상태 검증 · 멱등 처리, stale 재 plan | — |
| 배포 · 결과 | 레인 · 로그 · 결과 표시 | `terraform apply`, 락, SSE, digest · 헬스 확인 | — |
| 롤백 | 환경 선택 · 확인 Dialog · 롤백 배포 표시 | 이전 성공 배포의 커밋 + 검증된 스크립트로 새 배포, plan · 승인 · apply | — |
| 비밀값 | 입력 폼 (값은 다시 안 보여줌) | 보관 · 전달 (`[미정]`) | — |

**웹이 하지 않는 것:** GitHub API · 클라우드 API 직접 호출, Terraform 실행, 비밀값을 브라우저 저장소에 보관.

---

## 5. 일정

**와이어프레임의 모든 화면(W-00 ~ W-14, W-00b, W-05b, L-01 ~ L-03)을 9/30에 목업으로 완성했어요** (#15 · #18). W-02b는 범위 제외예요. 10/1 ~ 10/2는 서버 API가 열리는 대로 목업을 걷어내요.

| 날짜 | 웹 | 백엔드에 필요한 시점 |
|---|---|---|
| D1 (9/30) ✅ | Vite 프로젝트, `tokens.css`(라이트 · 다크), **기본 컴포넌트**: Core(Button · Status Badge · Env Tag · Input · Checkbox · Env Select Card · Logo), Primitives(Icon · Spinner · Toggle · Select · Select Menu · Progress Bar · Tooltip · Avatar · Skeleton · Tab Item · Alert · Toast · Dialog · Empty State), 레이아웃(Sidebar · Nav Item · Project Menu) | 이 문서 §6 리뷰 → `WR-xx` 이름 확정 |
| D2 (10/1) | ~~로그인 · 흐름 화면~~ → 9/30에 완성. 서버가 열리면 로그인 · W-01 · W-05 · W-07부터 실서버 연결 (5초 폴링) | 인증 R-01·R-02, 개발 서버 R-08, API A-01 · A-02 · A-04, **WR-02 · WR-09** (서버 D2 약속) |
| D3 (10/2) | ~~W-09 ~ W-14 · L-01 ~ L-03~~ → 9/30에 완성. 승인 · 결과 · 이력 서버 연결, 폴링 → SSE, 전체 흐름 1회 통과 · 데모 리허설 | API A-03 · A-05 · A-06 · A-07 · W-01, SSE, WR-03 · WR-06 · WR-07 · WR-08 · WR-11 · WR-14 (서버 D3 약속) |
| 10/3 | 10:00 제출. 남은 화면 서버 연결, 버그 수정, **목업 0개 확인**. 24:00 전체 동작 | — |
| 10/4 | 본선 발표 (설계 문서 2분 + 라이브 데모 3분) | — |

- 화면 완성과 서버 연결은 따로 가요. 서버 API가 늦어지면 화면은 목업으로 먼저 완성하고, 서버가 열리는 대로 바꿔요
- W-10 환경 추가는 범위가 정해지지 않았어요 (§7). 회의에서 빼기로 하면 빼고, 그전까지는 와이어프레임대로 만들어요
- 10/3 제출 전 남은 목업은 전부 보고해요 (루트 §4-6)

---

## 6. 백엔드 요구사항

- 앱과 같이 쓰는 API는 `ios/SPEC.md` §6의 ID · 이름을 그대로 써요 (9/29 서버 확정). 여기서 다시 적지 않아요
- 웹 때문에 **새로 필요한 건 `WR-xx` 🆕**로 적었어요. **9/30 은현 님 답변([PR #9](https://github.com/Softbank-Hackathon-2026-Team-Daisy/unibloom/pull/9))**을 반영했어요. 서버가 확정한 건 `(가칭)`을 뗐고, 필드는 OpenAPI가 나오면 맞춰요 (루트 §6 3단계)
- 서버의 단일 원천은 OpenAPI 문서(springdoc)예요. 노션 「Backend API Endpoint」는 은현 님이 확정본으로 이어서 고쳐요

### 6-0. 앱과 같이 쓰는 것 (`ios/SPEC.md` §6)

| ID | 웹에서 쓰는 곳 | 비고 |
|---|---|---|
| R-01 ~ R-08 공통 | 전체 | 인증은 Bearer 하나. 에러 · 목록 · 시간 규칙 v0.1 그대로 |
| API A-01 `GET /projects` | 사이드바 프로젝트 전환 | |
| API A-02 `GET /projects/{id}/targets/status` | W-01, 사이드바 환경 목록 | digest 필드 추가 요청 → WR-09 |
| API A-03 `GET /projects/{id}/deployments` | W-01 최근 실행, W-09, 사이드바 승인 대기 배지 (`awaiting_approval` 필터) | |
| API A-04 `GET /deployments/{id}` | W-05 · W-05b · W-07 · W-08 | `attempt`는 "시도 n/3" |
| API A-05 `GET /deployments/{id}/plan` | W-06 요약 | 리소스 전체 목록은 WR-06 |
| API A-06 `GET /projects/{id}/builds` | W-03 | |
| API A-07 `GET /deployments/{id}/logs` | W-07 로그 채우기 | 웹은 **M** |
| E-01 · E-02 SSE | W-03 · W-05 · W-07, L-xx 완료 감지 | `log.batch`는 웹에서 **M** |
| API W-01 `POST /deployments/{id}/approvals` | W-06 승인 · 거절 | 409 → 최신 상태 다시 불러오기 |

### 6-0-1. 실서버 연결 현황 (10/2, #38 머지 기준)

| API | 상태 | 웹에서 맞춘 것 |
|---|---|---|
| R-02 `POST /auth/token` · R-03 `GET /auth/me` | ✅ 실서버 | 역할 `owner` · `viewer`, 사이드바 사용자 이름 · 역할. 틀린 비밀번호도 세션 만료로 보내지 않아요 |
| A-01 `GET /projects` · A-12 `GET /projects/{id}` | ✅ 실서버 | 첫 화면 = 첫 프로젝트, 사이드바 프로젝트 목록, W-13 `default_branch` · `repository_url` · `manifest_path`. `build` · `registry` · `webhook_last_at`은 미제공 |
| A-02 `GET /projects/{id}/targets/status` | ✅ 실서버 | `{ items, next_cursor }` 봉투, `connection_state`, `current: null` = "확인된 배포 없음", `health: unknown` = "확인 전", digest가 하나도 없으면 동일성 "확인 전" |
| A-06 `GET /projects/{id}/builds` | ✅ 실서버 | `queued` "대기 중", 커밋 메시지 · 작성자 · 시각 없으면 "—", `image_digest` · `images[]`, W-04로 `?build=source_version_id` |
| A-03 `GET /projects/{id}/deployments` · A-04 `GET /deployments/{id}` (#46 · #48) | ✅ 실서버 (#42~#48 머지 후) | 목록 · 상세 같은 모양. `version` 없음 → 짧은 커밋, `kind` null, 대상 `step` · `attempt` null → 상태로 추정 · "시도 —", `pending_approvals` |
| 배포 시작 `POST /projects/{id}/deployments` · 승인 · 취소 · 재시도 `POST /deployments/{id}/retry` · 롤백 (#42) | ✅ 실서버 (#42 머지 후) | 응답 `{ id, project_id, state }`. 시작 `{ source_version_id, target_ids }`, 승인 `{ decision, confirm_text, items }`(빈 items는 보내지 않음), 취소 · 재시도 `{ target_ids }`, 롤백 `{ target_ids, reason }` |
| WR-04 `GET /projects/{id}/targets` (#42) | ✅ 실서버 (#42 머지 후) | 봉투, `reuse` null → "판단 전", `connection.checked_at` null |
| A-05 `GET /deployments/{id}/plan` · WR-06 `?detail=resources` (#51) | ✅ 실서버 | `summary` · `plan_text` null, 현재 plan 없는 대상은 빠짐, `ai_usage` 토큰 · 원화 · 환율 null 가능 · `unknown_calls`. 리소스별 월 비용 없음 |
| SSE `GET /projects/{id}/events` · `GET /deployments/{id}/events` (#42) | ✅ 실서버 | 이벤트가 오면 스냅샷(A-02 · A-03 · A-04 · A-05 · A-06)을 다시 읽어요(300ms 묶음). 붙어 있으면 폴링은 30초 안전망, 끊기면 5초. W-07 로그는 `log.batch`로 받아서 A-07 없이도 보여요. 사이드바 연결 표시가 실제 상태 |
| A-07 로그(#56) · WR-02 연결 · WR-13 해제(#59) · WR-11 AI 호출별(#60) | ✅ 실서버 (서버 PR 머지 후) | 로그 봉투 · 소문자 level → 대문자, 콘솔 줄(target_id null) "common", W-07은 A-07로 이전 로그 + SSE로 새 줄(seq로 합침). W-02 `manifest: null` → "검증 전"으로 W-03. W-12 빈 기록은 "기록 없음"(AI 안 씀 아님). 전환 로딩은 20초 지나면 화면을 보여줘요 |
| WR-10 스크립트 목록 (#68) | ✅ 실서버 | 봉투 `{ items }`(`next_cursor` 늘 null). `origin` null = "출처 미확인"(AI 없이 기준 모듈을 쓴 경로 · 출처 모름, AI 생성이라고 하지 않음), `attempt` null이면 시도 숨김, `plan: false` = "plan 없음"(`risks` null), `last_used_at` null = "—", `discarded` = 원본을 더 쓸 수 없음(실패 아님), `reuse_count`는 성공한 재사용만. 파일 내용 · 기준 이미지 · 입력 · 토큰은 서버에 없어 "—" |
| 스크립트 내용(WR-07), manifest(WR-03), 연결 테스트 · 리소스(A-10 · A-11), 비밀값(WR-12) | ⏳ 목업 | 실서버 모드에서 스크립트 칸은 목업 코드 대신 "서버 연결 뒤에 보여요" | 실서버 모드에서 연결 테스트 · 리소스 버튼은 꺼요. SSE(`GET /deployments/{id}/events` · `/projects/{id}/events`)는 서버에 열렸지만 웹은 5초 폴링 유지 — 다음 PR |

**개발 서버 (10/2, 은현 님):** API `https://api.unibloom.cloud`(지금 #38 범위 — 이 PR의 `SERVER_READY`와 같아요), 웹 `https://www.unibloom.cloud`. 개발 API는 CORS로 localhost를 막아서, 로컬 웹은 Vite 프록시로 붙어요: `.env.local`에 `VITE_API_BASE_URL=/api` · `VITE_PROXY_TARGET=https://api.unibloom.cloud` · `VITE_USE_MOCK=false`.

로컬 확인: `main`의 서버를 로컬 Postgres로 띄우고 `VITE_API_BASE_URL=http://127.0.0.1:8080` · `VITE_USE_MOCK=false`로 owner · viewer 로그인, 개요 · 빌드(대기 중 → 완료) · 설정을 확인했어요.

### 6-1. 웹 신규 요구사항

| ID | 메서드 · 경로 | 화면 | 요청 · 응답 요약 | 우선 | 서버 답변 (9/30) · 제공 |
|---|---|---|---|---|---|
| WR-01 🆕 | **SSE 인증 방식** | 전체 | 브라우저 `EventSource`는 `Authorization` 헤더를 못 붙여요 | M | ✅ **`fetch` 스트리밍으로 확정.** 서버 변경 없음. 헤더 · 이벤트 형식은 §6-2 |
| WR-02 🆕 | `POST /projects` | W-02 | `{ repository, branch }` → `Project` + `deploy.yaml` 검증 결과 | M | ✅ 그대로. **D2** |
| WR-03 🆕 | `GET /projects/{id}/manifest` | W-02 · W-13 | 파싱된 `deploy.yaml` (포트 · 헬스체크 · env · secrets 이름 · DB) + 오류 목록 | M | ✅ 경로 확정. 모양은 `deploy.yaml` 스키마(팀 결정) 뒤. **D3** |
| WR-04 🆕 | `GET /projects/{id}/targets` | W-04 · W-10 | 대상 환경 목록 + `reuse` · `connection` (§6-4) | M | ✅ 별도 엔드포인트로. A-02(현황)와 용도가 달라서 합치지 않아요. 공통 필드는 같은 모델 |
| WR-05 🆕 | `POST /projects/{id}/deployments` | W-04 | `{ commit, target_ids[], strategy: "recreate" }` + `Idempotency-Key` → `Deployment` (즉시 반환) | M | ✅ 이 경로로 확정. 생성만 하위 경로, 조회 · 조작은 `/deployments/{id}/…` 최상위 |
| WR-06 🆕 | `GET /deployments/{id}/plan?detail=resources` | W-06 | 환경별 **리소스 전체 목록**(주소 · create/update/delete) + plan 텍스트 | M | ✅ 그대로. **D3** |
| WR-07 🆕 | `GET /deployments/{id}/targets/{target_id}/script` (가칭) | W-05 · W-11 | 생성된 Terraform 파일 목록과 내용 | M | 승환 님 산출물이라 9/30 18시 백엔드 회의에서 확인. 비밀값 필터는 서버. **D3** |
| WR-08 🆕 | `POST /deployments/{id}/cancel` | W-05 · W-07 | apply 전에는 취소, 이후는 중단 요청 | S | ✅ 그대로. 중단 요청은 즉시 종료를 보장하지 않아요. **D3** |
| WR-09 🆕 | A-02 · 결과에 **이미지 digest** 필드 | W-01 · W-08 | 환경별 `image_digest` | M | ✅ 넣어요. 웹훅 수신 때 같이 받고 A-02에 필드 추가(앱 영향 없음). **D2** |
| WR-10 🆕 | `GET /projects/{id}/scripts` (가칭) | W-11 | 검증된 스크립트 목록 (환경 · 버전 · 만든 방식 · 시도 · 검증 결과 · 재사용 횟수 · 마지막 사용 · 폐기 여부) | S | 승환 님 영역. 이 필드 목록이 #7의 "검증된 코드 · 재사용 조건 저장 구조"의 답이 돼요. **D3~** |
| WR-11 🆕 | 합계: **A-05 plan 응답의 `ai_usage`** · 호출별: **`GET /projects/{id}/ai-usage?deployment_id=`** | W-12 · W-06 | 배포 한 건의 호출 · 토큰 · 비용 · 호출 기록 | S | ✅ 10/1 서버 결정(#13). `status`는 **LLM 호출 성공 · 실패**(화면 "호출 성공 · 호출 실패"). 확인 못 한 토큰 · 비용은 0 대신 `null`, `note`(수정 이유)는 제공 약속 없음. 경로 · 필드는 OpenAPI로 맞춰요 |
| WR-12 🆕 | `PUT /projects/{id}/secrets/{name}` (가칭) | W-13 | 값 쓰기만. 읽기 API 없음 | S | 맞아요. 전달 방식이 팀 결정 대기 `[미정]` |
| WR-13 🆕 | `DELETE /projects/{id}` | W-13 | 프로젝트 연결 해제. 인프라는 지우지 않아요 | S | ✅ 그대로. 확인 Dialog에서 환경 이름 입력 |
| WR-14 🆕 | `POST /deployments/{id}/rollback` | W-09 | `{ target_ids[], reason }` + `Idempotency-Key` → `Deployment` (`kind: "rollback"`, `rolled_back_from`) | M | ✅ **범위에 넣어요** (은현 님 담당). 이전 성공 배포의 커밋 + 그때 검증된 스크립트로 재배포, 환경 선택 가능, plan · 승인을 거쳐요 |

### 6-1-1. 앱 요청 중 웹도 쓰는 것 ([#13](https://github.com/Softbank-Hackathon-2026-Team-Daisy/unibloom/issues/13))

승준 님이 앱 화면용으로 서버에 요청한 것 중 웹 화면에도 같은 버튼 · 칸이 있는 것이에요. ID는 `ios/SPEC.md` §6-8 그대로 쓰고, 받을지 · 이름 · 모양은 서버가 정해요. 전부 S이고, 없으면 웹도 버튼 비활성 · "—"로 보여줘요.

| ID | 메서드 · 경로 (가칭) | 웹 화면 | 비고 |
|---|---|---|---|
| R-09 | ~~`POST /auth/demo`~~ | W-00 "데모 계정으로 둘러보기" | ❌ 만들지 않아요 (#13 10/1). 따로 받은 viewer 계정으로 `/auth/token`. 실서버 모드에서 버튼은 안내만 하고, 비밀번호는 웹에 넣지 않아요 |
| A-10 | `POST /targets/{id}/test` | W-10 "연결 테스트" | |
| A-11 | `GET /targets/{id}/resources` | W-10 "리소스 보기" | |
| A-12 | `GET /projects/{id}` | W-13 저장소 카드 | |

기존 응답의 선택 필드 추가(`Deployment.version` · `commit_message`, `targets[].steps[]` 등)도 #13을 따라요. 웹은 필드가 없으면 "—"로 보여줘요.

### 6-1-2. 선택 필드 요청 (가칭, 10/1 #13에 코멘트로 전달)

화면에 필요한데 아직 응답에 없는 필드예요. 없으면 화면이 단계 · 상태로 추정하거나 "—"로 보여줘서 막히지는 않아요. 대부분 #13(앱 요청)과 겹쳐요.

| 필드 | 쓰는 곳 | 비고 |
|---|---|---|
| `Deployment.targets[].steps[] { name, state, duration_ms }` | W-05 · W-05b · W-07 단계 · 소요 시간 | #13. Jenkins 단계는 `daisy-cd-plan`: Prepare → Infra code → Plan → Summary, `daisy-cd-apply`: Verify → Apply → Health check (#17). 실행 안 한 단계(`NOT_EXECUTED`)는 `skipped`로 "건너뜀" 표시 — 값 이름은 은현 님과 확인 (가칭) |
| `Deployment.targets[].title` · `health_summary` | W-07 레인 · W-08 결과 카드 | #13. 헬스는 1회 측정이라 `"200 OK · 120ms"` 형식, p95 없음 (#17 인프라) |
| `PlanDetail.resources[].monthly_cost_krw` | W-06 리소스별 월 비용 | 🆕 새 요청 |
| 동일성 검증 "앱 버전" · "환경변수 해시" (환경별) | W-01 · W-08 동일성 검증 표 | 🆕 새 요청. 지금은 digest · 커밋 · 배포 버전 · 헬스체크만 |
| `Build.pipeline.steps[]` · `digest` | W-03 | #13 |
| `Target`의 `runtime` · `location` · `access_method` · `exposure` · `state_backend` · `current_commit` | W-10 | #13. `state_backend`는 "S3 (잠금)" · "GCS (잠금)"처럼 서버가 준 이름 그대로, 온프레미스는 미정 (#17) |
| `Script`의 `base_commit` · `input` · `ai_tokens` · `storage` · `created_at` · `files` | W-11 | #13 |
| `Manifest.raw` (deploy.yaml 원문) | W-13 | #13 |
| `Project`의 `build` · `registry` · `webhook_last_at` | W-13 | #13 (A-12) |

승환 님 확인 대기(#9 코멘트): WR-06 **plan 원문**은 비밀값 처리 때문에 제공 여부 미정 → 웹은 원문이 없으면 리소스 목록만 보여줘요. `reuse.available` 판단 기준, 롤백 때 manifest를 어디까지 복원할지도 서버끼리 정해요.

### 6-2. 실시간 (SSE)

- **연결 방식 (WR-01 확정):** `fetch`로 `Authorization: Bearer` 헤더를 붙여 스트림을 열고 직접 파싱해요. 재연결은 `Last-Event-ID` 헤더
- **서버 형식:** `Content-Type: text/event-stream`, 이벤트는 `id`(= `seq`) · `event` · `data`(한 줄 JSON)만 쓰고 빈 줄로 끊어요. heartbeat 15초(연결 직후 한 번 바로)
- **`seq`는 채널(배포별 · 프로젝트별) 안에서 1부터** 시작해요. 다른 배포의 `seq`끼리 비교하지 않아요. 재생은 DB 기반이라 보관 기간이 없어요
- **CORS:** 허용 헤더 `Authorization` · `Content-Type` · `Last-Event-ID` · `Idempotency-Key` · `X-Request-ID`, 노출 헤더 `X-Request-ID`, 허용 Origin `localhost:5173` · `5174` · 개발 서버. **Vite 개발 서버 포트는 5173을 써요**
- 웹은 E-01 · E-02 이벤트를 **전부** 써요. 특히 `log.batch`(W-07), `plan.ready`(L-02 → W-06 전환), `deployment.completed`(W-08 전환)
- 🆕 **전환 로딩 끝 신호 (9/30 정정):** L-01은 첫 빌드가 나타날 때(`build.received` · A-06에 항목), L-02는 배포가 `queued`를 벗어날 때(첫 `step.started`), L-03은 한 환경이라도 `applying` 이후 상태가 될 때 넘어가요. L-02를 `plan.ready`로 두면 W-05를 건너뛰어서 고쳤어요. 이 이벤트들이 E-01 · E-02에 있으면 추가 작업은 없어요
- D2까지는 A-04 · A-02 · A-06을 5초 폴링해요

### 6-3. 백엔드가 가진 정보 중 웹이 꼭 받아야 하는 것

`ios/SPEC.md` §6-6에 더해서:

- 환경별 **이미지 digest** (동일성 검증)
- 환경별 **재사용 / 새로 생성 판단**과 그 이유 한 줄
- plan의 **리소스 전체 목록**과 생성된 Terraform 내용
- 배포 **생성자 · 시각 · 커밋 · 스크립트 버전** (W-09)

### 6-4. 데이터 모델

`Project` · `TargetStatus` · `Deployment` · `Plan` · `Build`는 `ios/SPEC.md` §6-7과 같은 모양을 써요. 웹은 아래를 더해요. 모두 `(가칭)`이고, 서버 OpenAPI가 나오면 맞춰요.

```jsonc
// TargetStatus에 추가 — WR-09
{ "image_digest": "sha256:9f3c…e1a" }

// Target — WR-04, W-04 · W-10 (9/30 서버 답변 모양)
{
  "target_id": "tgt_aws",
  "type": "onprem" | "aws" | "gcp",
  "name": "aws-prod",
  "reuse": { "available": true, "script_id": "scr_…", "reason": "검증된 스크립트 s3이 있어요" },  // 재사용 / 새로 생성 판단
  "connection": { "state": "ok" | "failed" | "unknown", "checked_at": "…" }
}

// Deployment에 추가 — WR-14 롤백, W-09
{ "kind": "deploy" | "rollback", "rolled_back_from": "dep_42" | null }

// PlanDetail — WR-06, W-06
{
  "target_id": "tgt_aws",
  "resources": [ { "address": "aws_ecs_service.app", "action": "create" | "update" | "delete" | "replace" } ],
  "plan_text": "…"                          // terraform show 출력. 비밀값 제외
}

// Script — WR-07 · WR-10, W-05 · W-11
{
  "script_id": "scr_…",
  "target_id": "tgt_aws",
  "version": "s2",
  "origin": "ai_generated" | "reused" | null, // null = AI 없이 기준 모듈 · 출처 미확인 (#68)
  "attempt": 2,                             // 통과한 시도 (n/3), 모르면 null
  "validation": { "validate": true, "plan": true, "risks": 0 },  // plan 없으면 risks null
  "status": "verified" | "discarded",       // discarded = 원본을 더 쓸 수 없음
  "reuse_count": 1,                         // 성공한 재사용만
  "last_used_at": "…",                      // 쓴 적 없으면 null
  "created_at": "…",                        // 검증을 마친 시각
  "files": [ { "path": "main.tf", "content": "…" } ]   // WR-07에서만
}

// AiUsage 합계 — API A-05 plan 응답의 ai_usage (W-06 · W-12). 확인 못 한 값은 null
{ "calls": 3, "tokens": 7920, "cost_krw": 206, "exchange_rate": 1380, "estimated": true }

// AiUsage 호출별 — GET /projects/{id}/ai-usage?deployment_id= (W-12, 10/1 서버 결정 · 필드는 가칭)
{ "items": [ { "at": "…", "target_id": "tgt_aws", "step": "generate" | "fix", "attempt": 2,
               "tokens": 1860 | null, "cost_krw": 48 | null,
               "status": "succeeded" | "failed" } ],   // LLM 호출 성공 · 실패
  "next_cursor": null }
```

---

## 7. 결정이 필요한 것 ❓

와이어프레임 NOTE의 Q번호(플로우차트 설계서 "확인이 필요한 부분")를 모았어요. 이미 정해진 건 줄을 그었어요.

- [x] ~~앱 범위 (ADR-007)~~ → **앱도 웹과 같은 전체 흐름** (10/1 팀장 결정, §1-1). `ios/SPEC.md` §1-1은 승준 님께 맞춰 달라고 요청
- [ ] **Q1 거절하면 어디로?** 종료 / W-04로 복귀 / AI 재생성 — 서버 · 팀. **그전까지 웹은 개요(W-01)로 돌아가요**
- [ ] **헬스체크 실패 시 자동 롤백을 할지** — 자동이면 승인 없이 인프라가 바뀌는 유일한 경로가 생겨요. 은현 님은 "사전 동의로 보고 넣자" 쪽 — 팀 회의
- [ ] **롤백 범위** — 서버는 수동 롤백을 넣기로 했지만(WR-14) 루트 `AGENTS.md` §12-4에는 `[미정]`이에요. 웹은 W-09 롤백을 만들어 뒀고, 회의에서 빼기로 하면 버튼만 숨겨요 — 팀 회의
- [ ] **Q2 빌드 · 테스트 실패 시** W-03에서 Failed + 실행 종료 + 알림으로 가정 — CI 담당 · 서버
- [ ] **Q3 main merge마다 실행이 하나씩 쌓이는 구조** 가정 — 서버
- [ ] **Q4 merge마다 W-04에서 환경을 고르나, 한 번 고른 환경으로 자동 진행하나** — 팀
- [ ] **Q5 위험 설정을 오류로 보고 AI 수정 루프에 넣나, 경고만 하나** — 서버(김승환)
- [ ] **Q6 재사용(태그만 교체)도 검증을 거치나** — 승인 화면에 plan이 필요해서 거친다고 가정 — 서버(김승환)
- [x] ~~Q7 3회는 환경별인가, 한 환경 실패 시 나머지는?~~ → **환경별, 한 환경이 3회 실패해도 나머지는 계속.** 그 환경은 `failed`, 배포 전체는 `partially_succeeded` (9/30 서버). W-05b에서 "빼고 계속" 버튼을 뺐어요
- [ ] **Q8 AI가 Dockerfile도 고치나** — 고치면 W-05 · W-11에 Dockerfile 탭 추가 — 서버(김승환)
- [x] ~~Q9 한 환경만 apply 실패 시~~ → **나머지는 유지하고 `partially_succeeded`로 표시.** 되돌리려면 W-09에서 그 환경만 골라 롤백 (9/30 서버 · 와이어프레임)
- [x] ~~Q10 배포 이후 단계(헬스체크 · URL · 롤백)를 흐름에 넣나~~ → **넣어요.** `health_check` 단계 + W-08 결과 + W-09 롤백(WR-14) (9/30 서버)
- [x] ~~업로드 입력(W-02b)을 유지하나~~ → **범위 제외.** 소스 업로드 API가 빠졌고, 빌드는 Jenkins가 해요 (9/30 회의) (노션 ADR "샌드박스 방식 제외", 9/30 서버)
- [ ] **환경 추가(W-10)를 예선 범위에 넣나** — "왜 AI인가" 후보 (b) — 팀
- [x] ~~`react-router` 추가~~ → 사용 (9/30, 김도영). ADR-006에 기록
- [x] ~~로그인 화면~~ → **W-00 · W-00b 추가** (9/30 와이어프레임)
- [ ] **웹도 앱과 같은 토큰으로 로그인하나, 토큰 만료 처리** — 가정: 같은 `POST /auth/token`, `401` → W-00 — 서버 답변 대기
- [x] ~~배포 상태 · 단계 값~~ → §2-5 (9/30 서버)
- [x] ~~상태 배지 색 매핑~~ → 와이어프레임 기준 (§2-5, 9/30)
- [x] ~~W-14 Mac 앱 호스팅 · 버전~~ → GitHub Releases 고정 주소 `mac-latest/Unibloom.dmg` + iPhone TestFlight (§2-3, 9/30 승준 님)
- [x] ~~롤백 · 연결 해제 확인 문구~~ → 환경이 여러 개라 환경 이름 대신 **프로젝트 이름**을 입력해요 (9/30, 웹)
- [x] ~~W-12 AI 사용량 API~~ → 합계는 A-05 plan 응답, 호출별은 `GET /projects/{id}/ai-usage?deployment_id=` (10/1 서버, #13). LLM은 Claude (9/30 21:27)
- [x] ~~실패한 환경 다시 시도~~ → 실패한 환경만 고른 **새 배포**, 시도 1/3부터 (9/30 서버, #13)
- [ ] **목록 응답 봉투** — 웹은 A-01 · A-03 · A-06만 `{ items, next_cursor }`, 나머지(A-02 · WR-04 · WR-07 · WR-10 · A-07)는 배열로 받아요. 앱은 전부 봉투. 노션 계약 v0.2는 "OpenAPI에서 명시" — 서버 확인 후 웹 · 앱을 한쪽으로 맞춰요
- [x] ~~인증 방식 · 브라우저 SSE~~ → Bearer 하나 (9/29), 브라우저는 `fetch` 스트리밍 (WR-01, 9/30)
- [x] ~~HTTPS 공개 주소~~ → 팀 도메인 HTTPS (9/29 회의, 서버 담당)

`[미정]` 팀 결정 대기: `deploy.yaml` 스키마, 레지스트리, 비밀값 전달 방식, Terraform state 저장소, 검증된 스크립트 저장 위치, LLM · 비용 단가.

---

## 8. 변경 기록

| 날짜 | 변경 | 작성 |
|---|---|---|
| 9/30 | 초안 작성: 와이어프레임 v1.0 · 디자인 시스템 확정본 기준, 백엔드 신규 요구 WR-01~14 | 김도영 |
| 9/30 | 일정: 와이어프레임 화면 전부 10/2까지. `react-router` 사용, Node 22 LTS · pnpm 9 확정 | 김도영 |
| 9/30 | 와이어프레임 수정 · 서버 답변 반영: W-00 로그인 추가, W-02b 범위 제외, W-05b 한 환경만 중단, 상태 값(§2-5), 롤백(WR-14) 범위 포함, WR-01 `fetch` 스트리밍, WR-04 · WR-05 모양 확정, W-12 배포별 보기, Q7 · Q9 · Q10 해결 | 김도영 |
| 9/30 | 승준 님 코멘트 반영: §1-1 앱 범위는 회의 안건으로 표시(ADR-007 기준 유지), §6-1-1 앱 요청(#13) 중 웹도 쓰는 R-09 · A-10 ~ A-12 연결 | 김도영 |
| 9/30 | W-14 Mac 앱 다운로드(Dialog) 추가 (와이어프레임 갱신) | 김도영 |
| 10/3 | 실서비스 점검 UX 개선(#102): 로그인 유지(`sessionStorage`), MOCK 배지 범위, 로그 환경별 탭, 실제 QR, 모바일 레이아웃 등 | 김도영 |
| 10/2 | 회의 반영: 대상 환경에 Azure 포함(서버 `ck_target_env` 추가 필요), 결과 URL은 새 탭 링크, 동일성 표 digest 줄여 보기 | 김도영 |
| 10/2 | WR-10 스크립트 목록 실서버(#68): 봉투, `origin` · `attempt` · `risks` · `last_used_at` null 처리, 폐기 뜻 정정 | 김도영 |
| 10/2 | 화면 언어 한국어 · English · 日本語 (#75): §3 화면 언어 · 폰트, 요청에 `Accept-Language` | 김도영 |
| 10/2 | 서버 #56 · #59 · #60: A-07 로그 · WR-02 · WR-13 · WR-11 실서버, 전환 로딩 20초 상한 | 김도영 |
| 10/2 | SSE 연결: 프로젝트 채널(AppLayout) · 배포 채널(W-05 · W-06 · W-07 · W-08), 이벤트 → 다시 읽기, 로그는 `log.batch`, 연결 시 폴링 30초 | 김도영 |
| 10/2 | #42 · #46 · #48 계약: 배포 목록 · 상세 · 생성 · 승인 · 취소 · 재시도(`/retry`) · 롤백 · WR-04 실서버, `version` · `step` · `attempt` null 처리 | 김도영 |
| 10/2 | 실서버 연결(#38): 서버에 열린 API만 실서버로(§6-0-1), 역할 `owner`, A-02 봉투 · `current` null 문구, A-06 `queued` · `source_version_id`, 승인 `items`, R-09 없음 | 김도영 |
| 10/1 | 배포 전체 `running` 문구를 "진행 중"으로 (생성 · 검증부터 apply까지 포함, 환경별 `applying` "배포 중"과 구분) | 김도영 |
| 10/1 | 서비스 이름 Daisy → **Unibloom** (Figma 로고 워드마크 "unibloom"). 팀 이름(Team Daisy) · GitHub 조직 이름은 그대로 | 김도영 |
| 10/1 | 앱 범위 확정: §1-1을 "웹과 앱이 같은 전체 흐름"으로, §7 앱 범위 해결 | 김도영 |
| 10/1 | 인프라 답(#17) 반영: W-03 Jenkins 로그 링크 제거 · 단계 이름, 헬스 1회 측정 형식, W-10 state 저장소 이름 | 김도영 |
| 10/1 | 리뷰 · 결정 반영(#18): W-12 데이터 출처(A-05 + ai-usage), 호출 성공 · 실패, 빌드 Jenkins, W-14 고정 주소, 다시 시도 = 새 배포, 목록 봉투 질문, `pages/image-build` | 김도영 |
| 9/30 | 화면 구현 반영(#15 · #18): 화면 경로 §2-6, 배지 색 확정, 전환 로딩 끝 신호 정정, 선택 필드 요청 §6-1-2, W-14 값 확정, 롤백 범위 `[미정]` 표시, 웹 담당 김도영(루트 §5-1), 일정 갱신 | 김도영 |
