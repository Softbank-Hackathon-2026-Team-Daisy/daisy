# AGENTS.md — web/ (웹 대시보드)

담당: 김도영 (`kimdoyoung1110`, 리드), 박승준 (`Seungjun1127`). 상태: v1 (2026-09-30).

루트 `AGENTS.md`를 먼저 따라요. 이 파일은 `web/`에만 해당하는 규칙을 더하고, 루트 하드 규칙(§4)을 느슨하게 하지 않아요. 제품 명세, 화면 목록, 백엔드 요청 전부는 [`SPEC.md`](./SPEC.md)에 있어요. **여기서 작업하기 전에 `SPEC.md`를 읽어요.**

## 1. 이 폴더가 하는 일

배포 흐름 **전체**를 돌리는 웹 대시보드예요 (ADR-007): 저장소 연결, 환경 선택, plan 확인 · 승인, 병렬 배포 진행, 결과 · 이력.

- 화면: W-01 ~ W-13, 전환 로딩 L-01 ~ L-03 (`SPEC.md` §2)
- 웹은 GitHub, 클라우드 API, Terraform에 직접 붙지 않아요. 모든 데이터는 Daisy 서버 API를 거쳐요
- 화면은 Figma [와이어프레임 v1.0](https://www.figma.com/design/5nqU4xotMh5jcsaDqOcTST/Team-Daisy-%EC%98%88%EC%84%A0?node-id=0-1), 모양은 [디자인 시스템](https://www.figma.com/design/5nqU4xotMh5jcsaDqOcTST/Team-Daisy-%EC%98%88%EC%84%A0?node-id=2-4)을 따라요 (둘 다 9/30 확정)

## 2. 이 파트가 의존하는 계약

`web/`는 다른 파트에 계약을 제공하지 않아요. 아래를 소비하고, 전부 server(하은현, 김승환) 소유예요.

| 계약 | 요구사항을 적는 곳 | 상태 |
|---|---|---|
| REST API 경로 | `ios/SPEC.md` §6 (공용), `SPEC.md` §6-1 (웹 신규 `WR-xx`) | 공용은 9/29 서버 확정. `WR-xx`는 `(가칭)` |
| 응답 필드 | `ios/SPEC.md` §6-7, `SPEC.md` §6-4 | 서버 OpenAPI가 나올 때까지 `(가칭)` |
| SSE 채널 · 이벤트 | `ios/SPEC.md` §6-3, `SPEC.md` §6-2 | 이름 확정. 서버 SSE는 D3, 그전까지 5초 폴링 |
| 인증 | `ios/SPEC.md` §6-1 | Bearer 하나 (REST · SSE). **브라우저 SSE 방식은 `WR-01`로 서버가 결정** |
| 배포 상태 · 단계 이름 | 서버 | 서버 이름을 그대로 따라요. 모르는 값은 중립 상태로 표시하고 죽지 않아요 |
| `deploy.yaml` 스키마 | 루트 §12-5 | `[미정]`: 팀 회의만 |

전부 루트 §6의 3단계예요: 이름과 모양은 서버 담당자가 정해요.

## 3. 작업 방법

1. 서버와 통신하는 코드를 쓰기 전에, 필요한 엔드포인트 · 필드 · 이벤트를 `SPEC.md` §6(공용은 `ios/SPEC.md` §6)에서 찾아요.
2. **없으면 먼저 `SPEC.md` §6-1에 `(가칭)` 🆕 `WR-xx` 행으로 추가**해요 (ID, 메서드 · 경로, 필드, 웹에 왜 필요한지). 그다음 그 항목 기준으로 코드를 써요.
3. `SPEC.md` §6-4와 `src/api/` 타입은 모양을 똑같이 유지해요. 하나를 바꾸면 같은 커밋에서 다른 하나도 바꿔요.
4. `(가칭)` 표시가 없는 이름은 담당자에게 묻지 않고 바꾸지 않아요. 서버와 합의된 이름이에요.
5. 서버가 실제 계약을 공개하거나 바꾸면 `SPEC.md`와 루트 §8 모순 확인을 해요. 서버 결정에 웹을 맞추고, 일치하는 항목의 `(가칭)`을 떼요.
6. 화면은 와이어프레임과 디자인 시스템 컴포넌트로 만들어요. 디자인 시스템에 없는 색 · 글자 크기 · 간격 · radius를 새로 만들지 않아요. 필요하면 담당자에게 물어요.
7. 작업이 끝나면 추가하거나 바꾼 `SPEC.md` 항목(ID, 무엇, 왜)을 보고에 적고, 새 `WR-xx`마다 서버 이슈 초안을 써요 (루트 §9).

## 4. 목업

`ios/`와 달리 웹은 서버 API가 나오기 전(D2~D3)에도 화면을 만들기 위해 목업을 써요.

- 모든 목업은 표시해요: 코드에 `// MOCK:`, 목업 데이터를 보여주는 화면에는 눈에 보이는 `MOCK` 배지 (루트 §4-6). 데모에서도 숨기지 않아요
- 목업은 `src/mocks/`에만 둬요. 화면은 `src/api/`로만 데이터를 받아서, 실서버로 바꿀 때 화면 코드를 건드리지 않아요
- 목업 데이터는 `SPEC.md` §6-4 모양을 그대로 따르고, 실제 토큰 · 비밀번호 · 자격증명이 든 URL을 넣지 않아요
- 와이어프레임 숫자(`a1b2c3d`, `₩82`, URL)는 예시예요. 목업 안에서만 써요
- 서버 API가 열리면 바로 바꾸고, 데모 전에 남은 목업을 전부 담당자에게 보고해요

## 5. 디자인 시스템

출처: Figma 「디자인 시스템」 페이지. 섹션 `01 · Foundations`(토큰), `02 · Core`, `03 · Icons & Primitives`, `04`~`06`(화면별 컴포넌트), `07 · Loading`, `08 · Navigation`. **Figma와 이 절이 다르면 Figma가 맞아요.** 같은 PR에서 이 절을 고쳐요.

### 5-1. 원칙

- **노란색(`--color-primary`)은 배포 버튼과 현재 단계에만.** 활성 메뉴 · 링크 · 강조에 쓰지 않아요
- **그림자 없음.** 겹치는 요소(메뉴 · Dialog · Toast)는 1px `--color-ink` 테두리
- 기본 테두리 1px `--color-line`. 선택 · 포커스는 2px `--color-focus`
- 원형은 상태 점과 아바타만. 알약 모양 금지
- 라이트 · 다크 둘 다 있어요. 색은 토큰으로만 쓰고 하드코딩하지 않아요

### 5-2. 색 토큰

| 토큰 | 라이트 | 다크 | 용도 |
|---|---|---|---|
| `--color-bg` | `#ffffff` | `#0b1026` | 페이지 배경 |
| `--color-surface` | `#f4f5f7` | `#141c3f` | 카드 · 패널 · 사이드바 |
| `--color-surface-strong` | `#e9ebef` | `#1e2a5a` | 선택된 카드, Secondary 버튼, 활성 메뉴 |
| `--color-line` | `#d8dce3` | `#2f3f82` | 기본 테두리 · 구분선 |
| `--color-ink` | `#0b1026` | `#f4f5f7` | 본문 글자, 겹침 테두리 |
| `--color-ink-muted` | `#5b6275` | `#9aa3bd` | 보조 글자 |
| `--color-primary` | `#ffd23f` | `#ffd23f` | 배포 버튼 · 현재 단계만 |
| `--color-on-primary` | `#0b1026` | `#0b1026` | primary 위 글자 |
| `--color-focus` | `#0b1026` | `#f4f5f7` | 포커스 · 선택 테두리 |
| `--color-success` | `#0f8a5f` | `#4ade9b` | 성공 |
| `--color-danger` | `#d92d20` | `#f97066` | 실패, Destructive 버튼, plan 삭제 |
| `--color-warning` | `#b54708` | `#fdb022` | 주의 |
| `--color-running` | `#1f4fd8` | `#7fa8ff` | 배포 중 |
| `--color-rolledback` | `#6b4fbb` | `#b9a6f2` | 롤백됨 |
| `--color-env-onprem` | `#14b8a6` | `#14b8a6` | 환경 태그: 온프레미스 |
| `--color-env-aws` | `#f97316` | `#f97316` | 환경 태그: AWS |
| `--color-env-gcp` | `#3b82f6` | `#3b82f6` | 환경 태그: GCP |
| `--color-env-azure` | `#0ea5e9` | `#0ea5e9` | 환경 태그: Azure |

### 5-3. 타이포그래피

글꼴: 글은 **IBM Plex Sans KR**, 코드 · 로그 · 해시 · 오버라인은 **IBM Plex Mono**.

| 스타일 | 글꼴 | 크기 / 줄 높이 | 굵기 | 용도 |
|---|---|---|---|---|
| `display` | Plex Sans KR | 40 / 48 | 600 | 큰 제목 |
| `h1` | Plex Sans KR | 24 / 32 | 600 | 페이지 제목 |
| `h2` | Plex Sans KR | 18 / 26 | 600 | 섹션 제목 |
| `body` | Plex Sans KR | 15 / 22 | 400 | 본문 |
| `body-sm` | Plex Sans KR | 13 / 20 | 400 | 보조 설명 |
| `label` | Plex Sans KR | 13 / 18 | 500 | 버튼 · 폼 라벨 |
| `mono` | Plex Mono | 13 / 20 | 400 | plan 출력 · 해시 |
| `mono-sm` | Plex Mono | 12 / 18 | 400 | 로그 줄 |
| `overline` | Plex Mono | 11 / 16 | 500 | 대문자 오버라인, 자간 8% |

### 5-4. 간격 · radius

- 간격 (기준 4): `--space-1` 4, `--space-2` 8, `--space-3` 12, `--space-4` 16, `--space-6` 24, `--space-8` 32, `--space-12` 48, `--space-16` 64 (px)
- radius: `--radius-none` 0 (기본), `--radius-sm` 2 (배지 · 태그), `--radius-md` 4 (버튼 · 카드). **4 초과 금지**

### 5-5. 컴포넌트

`src/components/`에 한 번 만들고 재사용해요. **Figma 컴포넌트 이름 = React 컴포넌트 이름** (Status Badge → `StatusBadge`).

- **Core**: Button (Primary · Secondary · Outline · Ghost · Destructive / Default · Hover · Disabled), Status Badge, Env Tag, Input (Default · Focus · Error · Disabled), Checkbox, Env Select Card, Logo
- **Primitives**: Icon (20px), Spinner, Toggle, Select, Select Menu, Progress Bar, Tooltip, Avatar (Human · AI), Skeleton, Tab Item, Alert, Toast
- **흐름 S0~S3**: Step Indicator, Stepper, Source Option Card, Project List Item, Run List Item, Dropzone, Info Row, Detected Chip, Add Env Card
- **흐름 S4~S5**: Tabs, Code Block, Resource Diff Row (Create · Update · Delete), Approval Bar, Step Item, Deploy Lane, Log Viewer, Connection Indicator
- **결과 · 이력**: Result Card, Parity Table, History Table Row, Dialog, Empty State
- **로딩 · 내비게이션**: Infra Block, Transition Loader, Nav Item (Expanded · Collapsed), Sidebar (Expanded · Collapsed), Project Menu

문구

- Status Badge: 대기 중 · 배포 중 · 성공 · 실패 · 주의 · 롤백됨
- Env Tag: 온프레미스 · AWS · GCP · Azure
- Stepper: 소스 입력 · 분석 · 대상 환경 · 계획 · 검증 · 배포 · 결과

### 5-6. 사이드바 · 로딩 규칙

- **사이드바:** 프로젝트 단위 메뉴(개요 · 배포 · 환경 · 이력 · 스크립트 / 아래쪽 AI 사용량 · 설정). 배포 흐름 화면(W-02~W-08, L-xx)에서는 64px, 그 밖에는 240px. 활성 메뉴는 `--color-surface-strong` 배경 + 왼쪽 2px ink 막대
- **W-06 "승인하고 배포"**는 노란 48px 버튼이고 화면에서 가장 큰 요소예요. 다른 화면의 CTA는 Secondary예요
- **전환 로딩 (Infra Block):**
  - `--color-ink` 한 색 (윗면 55% · 왼면 82% · 오른면 100%). 노란색 · 라벨 없음
  - 2.5D 아이소메트릭(2:1), 층 사이 틈 없음. 바닥은 고정, 그 위 같은 크기 블록 3개
  - Stack 0 → 1 → 2 → 3 → 한꺼번에 사라짐 → 0 반복. 블록마다 24px 위에서 450ms로 내려앉고(살짝 튕김), 3층이 다 쌓이면 600ms 머문 뒤 200ms 페이드아웃
  - 문구: 화면별 첫 고정 문구 → 01~10 반복. 한 문구당 3.5초, 바뀔 때 200ms 페이드(위로 4px). 줄 높이를 고정해서 블록 · 제목이 움직이지 않게
  - 문구 목록은 `src/pages/loading/captions.ts` 한 곳에서만 관리해요
  - 돌아가는 문구는 스크린리더가 읽지 않아요(`aria-live` 끔). 단계 변화만 알려요
  - `prefers-reduced-motion`이면 떨어지는 모션 없이 Stack 3에 고정
  - **3초 안에 끝나는 작업에는 쓰지 않아요**

## 6. 스택 · 구조

- React + Vite SPA, TypeScript (ADR-006). 최소 스택으로 시작하고, 라이브러리는 막힐 때만 추가해요 (§9)
- 라우팅은 `react-router`. 화면마다 URL이 있어서 푸시 · 공유 링크로 바로 들어올 수 있어요
- **Node 22 LTS**(`web/.nvmrc`), 패키지 매니저는 **pnpm 9**(`package.json`의 `packageManager`로 고정). `npm` · `yarn`은 쓰지 않아요. lock 파일은 `pnpm-lock.yaml` 하나만 커밋해요
- 스타일은 일반 CSS. §5 토큰을 `src/styles/tokens.css`에 CSS 변수로 둬요. UI 키트 · CSS 프레임워크 · 차트 라이브러리는 쓰지 않아요
- 서버 호출은 `fetch`, 실시간은 SSE이고 실패하면 5초 폴링. 긴 로그가 느려지면 TanStack Virtual을 추가해요

```
web/
├─ AGENTS.md
├─ SPEC.md
├─ .nvmrc              Node 22
├─ index.html · package.json · vite.config.ts
└─ src/
   ├─ main.tsx · App.tsx   진입점, 라우팅, 사이드바 레이아웃
   ├─ styles/              tokens.css (라이트 · 다크), base.css
   ├─ components/          디자인 시스템 컴포넌트 (§5-5)
   ├─ pages/               화면 단위 폴더 (SPEC.md §3-1), loading/captions.ts
   ├─ api/                 API 클라이언트, 타입, SSE · 폴링
   └─ mocks/               MOCK 데이터만 (§4)
```

## 7. 컨벤션

- 컴포넌트는 `PascalCase.tsx`, 파일 하나에 컴포넌트 하나. 훅은 `useXxx`, 나머지는 `camelCase`
- 한 화면에서만 쓰는 컴포넌트는 그 `pages/{page}/`에, 두 화면 이상에서 쓰면 `components/`로 옮겨요
- 서버 enum에는 모르는 값 처리를 둬서, 서버가 새 값을 추가해도 화면이 깨지지 않아요
- JSON은 서버의 `snake_case` 그대로 받아서 `src/api/`에서만 다뤄요
- 에러: `401` → 로그인, `409 STATE_CONFLICT` → 최신 상태 다시 불러오기, 승인 `403` → "읽기 전용 계정"
- `attempt`는 "시도 n/3"으로 보여줘요. 첫 생성을 포함한 총 시도 횟수라 1부터 시작하고, AI 수정은 최대 2번이에요. "재시도 횟수"로 쓰지 않아요
- AI 비용은 "추정"과 적용 환율을 같이 보여줘요
- 이미지 태그는 커밋 해시예요. `mono`로 보여주고 `latest`를 쓰지 않아요
- 사용자에게 보이는 문구는 한국어 해요체

## 8. 실행 방법

Node 22 LTS와 pnpm 9가 필요해요. Node 25에는 corepack이 없어서 pnpm은 직접 설치해요 (`npm i -g pnpm@9`).

```bash
cd web
nvm use            # .nvmrc → Node 22
pnpm install
pnpm dev
pnpm build
```

`(가칭)`: 테스트 · 린트 명령은 Vite 프로젝트를 만들 때 채워요.

## 9. 담당자에게 먼저 물어볼 것

- 의존성 추가 (ADR-006). 추가하면 §10과 노션 ADR-006에 이유를 남겨요
- 디자인 토큰 변경, §5에 없는 색 · 글자 크기 · 간격 · radius 추가
- 실제 토큰, 데모 계정 자격증명, 배포 대상과 관련된 것

## 10. 결정 기록

단계는 루트 §6 기준이에요. 1단계는 이 파트 안에서 확정이에요.

| 날짜 | 결정 | 이유 | 단계 |
|---|---|---|---|
| 9/29 | `web/CLAUDE.md` → `web/AGENTS.md` | 모든 에이전트 도구가 같은 규칙을 읽게 (#2, #5) | 1 |
| 9/30 | Figma 와이어프레임 v1.0 · 디자인 시스템(9/30 확정)을 UI 기준으로 | 화면과 모양의 단일 원천 | 1 |
| 9/30 | 서버 요청은 `SPEC.md` §6에 먼저 적고 코드를 써요 (`ios/`와 같은 흐름). 공용 API는 `ios/SPEC.md` ID, 웹 신규는 `WR-xx` | 웹 · 앱이 같은 백엔드를 쓰니 요구사항을 한 체계로 | 1 |
| 9/30 | 웹 화면 ID `W-xx`와 앱 승인 API `W-01`이 겹쳐서, 웹 문서에서는 API를 "API W-01"로 적어요 | ID 충돌 방지. 이름 변경은 `ios/` 담당 결정 | 1 |
| 9/30 | TypeScript, CSS 변수 토큰 + 일반 CSS, UI 키트 · 차트 라이브러리 없음 | ADR-006 최소 스택. Figma 토큰을 1:1로 | 1 |
| 9/30 | 화면 폴더는 `src/pages/` | Figma가 `src/pages/loading/captions.ts`로 지정 | 1 |
| 9/30 | 목업 허용. `src/mocks/`에만, 항상 표시 | 서버 API가 D2~D3에 나와서 그전에 화면을 만들어야 해요 | 1 |
| 9/29 | 서버 SSE 전(D3)까지 5초 폴링 | PR #1에서 서버와 합의 | 1 |
| 9/30 | 브라우저 SSE 인증 방식 (`WR-01`) | `EventSource`는 헤더를 못 붙여요. 서버가 결정 | 3 (`(가칭)`) |
| 9/30 | `react-router` 사용 | 화면 14개, 푸시 · 공유 링크로 W-06 같은 화면에 바로 들어와야 해요. ADR-006에 기록 | 1 |
| 9/30 | Node 22 LTS 고정, 패키지 매니저 pnpm 9 | LTS로 데모 서버 · CI와 맞춰요. pnpm은 설치가 빠르고, `package.json`에 없는 패키지를 못 불러와서 몰래 늘어나는 의존성을 막아요 | 1 |
