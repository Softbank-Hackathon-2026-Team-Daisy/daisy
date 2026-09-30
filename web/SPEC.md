# SPEC.md — Daisy 웹 대시보드 명세와 백엔드 요구사항

> 작성: 김도영 · 상태: **초안 (9/30)** · 참조: 루트 `AGENTS.md`, 노션 ADR-002·004·006·007, 플로우차트 설계서, `ios/SPEC.md`, `server/AGENTS.md`
> 화면은 Figma [와이어프레임 v1.0](https://www.figma.com/design/5nqU4xotMh5jcsaDqOcTST/Team-Daisy-%EC%98%88%EC%84%A0?node-id=0-1) (9/30 확정), 모양은 같은 파일의 [디자인 시스템](https://www.figma.com/design/5nqU4xotMh5jcsaDqOcTST/Team-Daisy-%EC%98%88%EC%84%A0?node-id=2-4)을 따라요.
>
> **백엔드 파트(하은현, 김승환)는 [§6 백엔드 요구사항](#6-백엔드-요구사항)부터 읽으면 돼요.** 앱과 같이 쓰는 API는 `ios/SPEC.md` §6의 ID를 그대로 쓰고, 웹 때문에 새로 필요한 것만 `WR-xx` 🆕로 적었어요.

> ⚠️ **ID 표기:** 이 문서에서 `W-01`~`W-13`은 **웹 화면 ID**(와이어프레임)예요. `ios/SPEC.md`의 승인 API `W-01`과 겹쳐서, 이 문서에서는 API를 항상 **"API W-01"**로 적어요.

---

## 1. 무엇을 만드나요

**배포 흐름 전체를 처음부터 끝까지 돌리는 웹 대시보드**예요 (ADR-007). 저장소를 연결하고, 환경을 고르고, AI가 만든 plan을 확인·승인하고, 병렬 배포를 지켜보고, 모든 환경이 같은 이미지로 떴는지 확인해요.

| 질문 | 웹이 답하는 화면 |
|---|---|
| 지금 어느 환경에 어떤 버전이 떠 있지? 다음에 할 일은? | W-01 개요 |
| 이 저장소를 배포하려면? | W-02 연결 → W-03 이미지 빌드 → W-04 환경 선택 |
| AI가 만든 Terraform은 통과했어? 몇 번 고쳤어? | W-05 생성 · 검증 (실패 시 W-05b) |
| 무엇이 바뀌는지 보고 승인하려면? | W-06 승인 |
| 배포가 어디까지 갔어? 모두 같은 이미지로 떴어? | W-07 배포 중 → W-08 결과 |
| 언제 무엇을 어디에 배포했지? | W-09 이력 |
| 환경 · 검증된 스크립트 · AI 사용량 · 설정은? | W-10 ~ W-13 |

### 1-1. 앱과의 역할 분리

웹과 앱은 코드를 공유하지 않고 **같은 백엔드 API만** 써요. 역할 분리 표는 `ios/SPEC.md` §1-1과 같아요. 웹 쪽 요약은 이래요.

- **웹만 하는 것:** 저장소 연결, 환경 선택, 배포 시작, plan 상세(리소스 전체 목록 · 스크립트), 환경 · 스크립트 · AI 사용량 · 설정 화면
- **웹과 앱이 같이 하는 것:** 승인 · 거절, 배포 진행 상태, 환경별 현재 버전, 이력
- 웹은 **GitHub, 클라우드, Terraform에 직접 붙지 않아요.** 모든 데이터는 Daisy 백엔드 API를 거쳐요

### 1-2. 데모 목표

- 발표에서 **웹으로 전체 흐름을 한 번에** 보여줘요: W-01 → W-02 → L-01 → W-03 → W-04 → L-02 → W-05 → W-06 → L-03 → W-07 → W-08
- 핵심 데모 포인트 두 가지
  - **이식성:** W-08의 동일성 검증 표(이미지 digest 비교) "3/3 일치"
  - **AI 활용:** W-05의 "시도 n/3", W-11의 재사용 · 폐기 이력, W-12의 "AI 0회 배포"
- 승인은 웹(W-06)과 앱 어느 쪽에서도 할 수 있어요. 발표에서는 앱 승인을 보여줄 수도 있어요 (`ios/SPEC.md` §1-3)

---

## 2. 화면 구성

와이어프레임은 1440px 기준이에요. 흐름은 이래요.

```
W-01 개요 → W-02 저장소 연결 (W-02b 업로드) → L-01 → W-03 이미지 빌드 → W-04 환경 선택
→ L-02 → W-05 생성 · 검증 (W-05b 중단) → W-06 승인 → L-03 → W-07 병렬 배포 → W-08 결과 → W-09 이력
메뉴 화면: W-10 환경 · W-11 스크립트 · W-12 AI 사용량 · W-13 설정
```

### 2-1. 흐름 화면

| ID | 화면 | 내용 | 우선 |
|---|---|---|---|
| W-01 | **개요** | 환경별 현재 버전(커밋 · 배포 시각 · 공개 URL · 헬스), "3/3 일치" 이식성 표시, 지금 할 일(승인 대기 → W-06, Secondary 버튼), 최근 실행 | M |
| W-02 | **애플리케이션 연결** (STEP 1) | 저장소 URL, 배포 기준 브랜치, `deploy.yaml` 확인. 데모 앱 sample-monolith 기준 (포트 8080, `/health`, DB 없음) | M |
| W-02b | 연결 · 업로드 | 폴더나 zip 업로드. 업로드 뒤 W-03과 합류 | S ❓ (§7) |
| W-03 | **이미지 빌드** (STEP 2) | main merge 감지, GitHub Actions 진행, 이미지 태그(커밋 해시) | M |
| W-04 | **배포할 환경 선택** (STEP 3) | 여러 환경 동시 선택, 카드에 재사용 / 새로 생성 미리 표시, 선택 요약 | M |
| W-05 | **인프라 코드 생성 · 검증** (STEP 4) | 환경별 진행과 "시도 n/3", 검증 단계, 생성된 스크립트 보기. SSE로 실시간 갱신 | M |
| W-05b | 배포를 중단했어요 | 한 환경이 3번 모두 실패했을 때 시도 기록과 환경별 상태 | M |
| W-06 | **변경 사항 확인 후 승인** (STEP 5) | 환경별 요약(+생성 ~변경 −삭제, 위험 설정), 환경별 plan 상세, AI 비용(추정). **노란 48px "승인하고 배포"가 화면에서 가장 큰 요소** | M |
| W-07 | **배포 중** (STEP 5) | 환경 3개 레인으로 `terraform apply` 병렬 진행, 로그 뷰어, 연결 상태 | M |
| W-08 | **배포 결과** (STEP 6) | 환경별 결과 카드(URL · 헬스), 동일성 검증 표(이미지 digest). TestFlight QR 자리 | M |
| W-09 | 배포 이력 | 버전별 이미지 · 스크립트 · 환경. 롤백 버튼과 확인 Dialog는 범위 결정 후 (§7 Q10) | M |

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
| W-12 | AI 사용량 | 호출 수 · 토큰 · 비용(추정) · 재사용으로 아낀 호출, 호출 기록 표. 차트는 넣지 않아요 | S (데모 효과 큼) |
| W-13 | 설정 | 저장소, `deploy.yaml`(읽기 전용), 비밀값(이름만, 값은 다시 볼 수 없음), 알림, 프로젝트 연결 해제(환경 이름 입력 확인) | S |

### 2-4. 사이드바 (9/30 결정)

- **프로젝트 단위 메뉴**: 개요 · 배포(승인 대기 배지) · 환경 · 이력 · 스크립트 / 아래쪽 AI 사용량 · 설정
- 상단 헤더를 사이드바로 합쳤어요. 위에서부터 로고, 프로젝트 전환(Project Menu), "새 배포", 메뉴, 환경 목록(상태 점), 실시간 연결 상태, 사용자
- **배포 흐름 화면(W-02~W-08, L-xx)에서는 64px 아이콘 바**, 그 밖에서는 240px
- 활성 메뉴는 `--color-surface-strong` 배경 + 왼쪽 2px ink 막대. 노란색은 쓰지 않아요

M = 예선 데모 필수, S = 선택

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
| 실시간 | SSE + 연결 실패 시 **5초 폴링** | 서버 SSE는 D3. 그전까지 폴링 (9/29 합의) |
| 긴 로그 | 느려지면 TanStack Virtual 추가 | 와이어프레임 W-07 NOTE (ADR-006) |
| 차트 | 쓰지 않아요 | W-12도 숫자 · 표로만 |
| 폰트 | IBM Plex Sans KR · IBM Plex Mono | 디자인 시스템 |
| 목업 | **허용.** `src/mocks/`에만 두고 `// MOCK:` + 화면 배지 | 서버 API가 D2~D3에 나와서, 그전에 화면을 만들어야 해요 (`AGENTS.md` §4) |

### 3-1. 폴더 구조

```
web/
├─ AGENTS.md                AI 에이전트 규칙 (이 폴더 전용)
├─ SPEC.md                  이 문서
├─ .nvmrc                  Node 22 LTS
├─ index.html
├─ package.json
├─ vite.config.ts
└─ src/
   ├─ main.tsx · App.tsx    진입점, 라우팅, 사이드바 레이아웃
   ├─ styles/               tokens.css (라이트 · 다크), base.css
   ├─ components/           디자인 시스템 컴포넌트 (Figma 이름 = 컴포넌트 이름)
   ├─ pages/                화면 단위 폴더
   │  ├─ overview/          W-01
   │  ├─ connect/           W-02 · W-02b
   │  ├─ build/             W-03
   │  ├─ targets/           W-04
   │  ├─ generate/          W-05 · W-05b
   │  ├─ approve/           W-06
   │  ├─ deploy/            W-07
   │  ├─ result/            W-08
   │  ├─ history/           W-09
   │  ├─ environments/      W-10
   │  ├─ scripts/           W-11
   │  ├─ ai-usage/          W-12
   │  ├─ settings/          W-13
   │  └─ loading/           L-01 ~ L-03, captions.ts
   ├─ api/                  API 클라이언트, 타입(§6-6과 1:1), SSE · 폴링
   └─ mocks/                MOCK 데이터만
```

### 3-2. 데이터 흐름

```
Page ──▶ hook ──▶ api/client ──────────▶ Daisy 백엔드 (REST)
  ▲        │ ◀── api/realtime (SSE → 이벤트, 실패 시 5초 폴링) ◀── Daisy 백엔드 (SSE)
  └ 상태 ──┘
                (서버가 없을 때만) api/client → mocks/
```

- 화면은 `src/api/`를 거쳐서만 데이터를 받아요. 목업 ↔ 실서버 전환이 화면 코드에 닿지 않아요
- SSE가 끊기면 `Last-Event-ID`로 다시 붙고, `resync`가 오면 스냅샷(API A-04)을 다시 불러요

---

## 4. 경계: 누가 무엇을 하나요

| 영역 | 웹 (김도영 · 박승준) | 백엔드 (하은현 · 김승환) | CI (담당 `[미정]`, Actions · Jenkins 결정 대기) |
|---|---|---|---|
| 저장소 연결 | 입력 · 결과 표시 | 프로젝트 저장, `deploy.yaml` 파싱 · 검증 | — |
| 이미지 빌드 | 진행 표시 | webhook 수신 · 저장 · 조회 API | Actions 빌드, 이벤트 전송 |
| 환경 선택 · 배포 시작 | 선택 UI, 배포 생성 요청 | 재사용 / 새로 생성 판단, 작업 큐 | — |
| 생성 · 검증 | 진행 · 스크립트 표시 | AI 생성 · 수정 루프, validate · plan · 위험 검사 | — |
| 승인 | 버튼 · 확인 문구 입력 | 권한 · 상태 검증 · 멱등 처리, stale 재 plan | — |
| 배포 · 결과 | 레인 · 로그 · 결과 표시 | `terraform apply`, 락, SSE, digest · 헬스 확인 | — |
| 비밀값 | 입력 폼 (값은 다시 안 보여줌) | 보관 · 전달 (`[미정]`) | — |

**웹이 하지 않는 것:** GitHub API · 클라우드 API 직접 호출, Terraform 실행, 비밀값을 브라우저 저장소에 보관.

---

## 5. 일정

**와이어프레임의 모든 화면(W-01 ~ W-13, W-02b, W-05b, L-01 ~ L-03)을 10/2(금)까지 만들어요.** 선택 화면은 따로 두지 않아요.

| 날짜 | 웹 | 백엔드에 필요한 시점 |
|---|---|---|
| D1 (9/30) | Vite 프로젝트, `tokens.css`(라이트 · 다크), **기본 컴포넌트**: Core(Button · Status Badge · Env Tag · Input · Checkbox · Env Select Card · Logo), Primitives(Icon · Spinner · Toggle · Select · Select Menu · Progress Bar · Tooltip · Avatar · Skeleton · Tab Item · Alert · Toast · Dialog · Empty State), 레이아웃(Sidebar · Nav Item · Project Menu) | 이 문서 §6 리뷰 → `WR-xx` 이름 확정 |
| D2 (10/1) | **흐름 화면 W-01 ~ W-08** (W-02b · W-05b 포함). 화면 전용 컴포넌트는 화면과 같이 만들어요. 목업으로 시작해서 서버가 열리면 W-01 · W-05 · W-07부터 실서버 연결 (5초 폴링) | 인증 R-01·R-02, 개발 서버 R-08, API A-01 · A-02 · A-04, **WR-01 · WR-04 · WR-05** |
| D3 (10/2) | 오전: **W-09 ~ W-13, L-01 ~ L-03** → 모든 화면 완성. 오후: 승인 · 결과 · 이력 서버 연결, 폴링 → SSE, 전체 흐름 1회 통과 · 데모 리허설 | API A-03 · A-05 · A-06 · A-07 · W-01, SSE, WR-xx 나머지 |
| 10/3 | 10:00 제출. 남은 화면 서버 연결, 버그 수정, **목업 0개 확인**. 24:00 전체 동작 | — |
| 10/4 | 본선 발표 (설계 문서 2분 + 라이브 데모 3분) | — |

- 화면 완성과 서버 연결은 따로 가요. 서버 API가 늦어지면 화면은 목업으로 먼저 완성하고, 서버가 열리는 대로 바꿔요
- W-02b · W-10 환경 추가 · W-09 롤백은 범위가 정해지지 않았어요 (§7). 회의에서 빼기로 하면 빼고, 그전까지는 와이어프레임대로 만들어요
- 10/3 제출 전 남은 목업은 전부 보고해요 (루트 §4-6)

---

## 6. 백엔드 요구사항

- 앱과 같이 쓰는 API는 `ios/SPEC.md` §6의 ID · 이름을 그대로 써요 (9/29 서버 확정). 여기서 다시 적지 않아요
- 웹 때문에 **새로 필요한 건 `WR-xx` 🆕**로 적었어요. 경로 · 필드는 모두 `(가칭)`이고 서버가 정해요 (루트 §6 3단계)
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

### 6-1. 웹 신규 요구사항

| ID | 메서드 · 경로 (가칭) | 화면 | 요청 · 응답 요약 | 우선 | 비고 |
|---|---|---|---|---|---|
| WR-01 🆕 | **SSE 인증 방식** | 전체 | 브라우저 `EventSource`는 `Authorization` 헤더를 못 붙여요 | M | 서버가 정해요. 후보: ① 짧은 수명 SSE 전용 토큰을 쿼리로 ② `fetch` 스트리밍으로 헤더를 붙여 직접 파싱(웹이 처리, 서버 작업 0) ③ 같은 도메인 쿠키. **웹은 ②도 가능해요** |
| WR-02 🆕 | `POST /projects` | W-02 | `{ repository, branch }` → `Project` + `deploy.yaml` 검증 결과 | M | 처음 한 번 연결 |
| WR-03 🆕 | `GET /projects/{id}/manifest` | W-02 · W-13 | 파싱된 `deploy.yaml` (포트 · 헬스체크 · env · secrets 이름 · DB) + 오류 목록 | M | 스키마는 팀 결정 대기 `[미정]` |
| WR-04 🆕 | `GET /projects/{id}/targets` | W-04 · W-10 | 대상 환경 목록 + 환경별 **재사용 / 새로 생성** 판단, 연결 상태 | M | 5-1 판단 결과를 카드에 미리 보여줘요 |
| WR-05 🆕 | `POST /projects/{id}/deployments` | W-04 | `{ commit, target_ids[] }` + `Idempotency-Key` → `Deployment` | M | 배포 시작. `server/AGENTS.md`의 "배포 생성 POST"와 같은 건이면 이름만 맞춰요 |
| WR-06 🆕 | `GET /deployments/{id}/plan?detail=resources` | W-06 | 환경별 **리소스 전체 목록**(주소 · create/update/delete) + plan 텍스트 | M | 앱은 요약만, 웹은 상세 (Resource Diff Row · Code Block) |
| WR-07 🆕 | `GET /deployments/{id}/targets/{target_id}/script` | W-05 · W-11 | 생성된 Terraform 파일 목록과 내용 | M | 비밀값이 들어가지 않게 서버에서 걸러 주세요 |
| WR-08 🆕 | `POST /deployments/{id}/cancel` | W-05 · W-07 | apply 전에는 취소, 이후는 중단 요청 | S | `server/AGENTS.md` 결정대로. 중단 요청은 즉시 종료를 보장하지 않아요 |
| WR-09 🆕 | A-02 · 결과에 **이미지 digest** 필드 | W-01 · W-08 | 환경별 `image_digest` | M | "3/3 일치" · 동일성 검증 표의 근거. 태그만으로는 같은 이미지인지 증명이 약해요 |
| WR-10 🆕 | `GET /projects/{id}/scripts` | W-11 | 검증된 스크립트 목록 (환경 · 버전 · 만든 방식 · 시도 · 검증 결과 · 재사용 횟수 · 마지막 사용 · 폐기 여부) | S | 저장 위치 `[미정]` |
| WR-11 🆕 | `GET /projects/{id}/ai-usage?cursor=` | W-12 | 합계(호출 · 토큰 · 비용 · 재사용으로 아낀 호출 · AI 0회 배포 수) + 호출 기록 | S | `ai_usage` 테이블 그대로. 비용은 추정 + 적용 환율 |
| WR-12 🆕 | `PUT /projects/{id}/secrets/{name}` | W-13 | 값 쓰기만. 읽기 API 없음 | S | 전달 방식 `[미정]` |
| WR-13 🆕 | `DELETE /projects/{id}` | W-13 | 프로젝트 연결 해제. 인프라는 지우지 않아요 | S | 확인 Dialog에서 환경 이름 입력 |
| WR-14 🆕 | `POST /deployments/{id}/rollback` | W-09 | 이전 배포로 되돌리기 + `Idempotency-Key` | S ❓ | 범위 결정 후 (§7 Q10) |

### 6-2. 실시간 (SSE)

- 웹은 E-01 · E-02 이벤트를 **전부** 써요. 특히 `log.batch`(W-07), `plan.ready`(L-02 → W-06 전환), `deployment.completed`(W-08 전환)
- 🆕 **전환 로딩 완료 신호:** L-01은 `build.received`(이미지 준비), L-02는 `plan.ready`, L-03은 첫 `step.started`(apply)로 넘어가요. 이 이벤트들이 E-01 · E-02에 있으면 추가 작업은 없어요
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

// Target — WR-04, W-04 · W-10
{
  "target_id": "tgt_aws",
  "type": "onprem" | "aws" | "gcp",
  "name": "aws-prod",
  "connection": "connected" | "disconnected" | "unknown",
  "plan_mode": "reuse" | "generate",        // 재사용(태그만 교체) / AI 새로 생성
  "plan_mode_reason": "검증된 스크립트 s3이 있어요"
}

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
  "origin": "ai_generated" | "reused",
  "attempt": 2,                             // 통과한 시도 (n/3)
  "validation": { "validate": true, "plan": true, "risks": 0 },
  "status": "verified" | "discarded",
  "reuse_count": 1,
  "last_used_at": "…",
  "files": [ { "path": "main.tf", "content": "…" } ]   // WR-07에서만
}

// AiUsage — WR-11, W-12
{
  "summary": { "calls": 12, "tokens": 48210, "cost_krw": 1240, "saved_calls": 9, "zero_ai_deployments": 3,
               "exchange_rate": 1400, "estimated": true },
  "items": [ { "at": "…", "target_id": "tgt_aws", "step": "generate" | "fix", "attempt": 2,
               "tokens": 1860, "cost_krw": 48, "status": "succeeded" | "failed" } ],
  "next_cursor": null
}
```

---

## 7. 결정이 필요한 것 ❓

와이어프레임 NOTE의 Q번호(플로우차트 설계서 "확인이 필요한 부분")를 모았어요. 이미 정해진 건 줄을 그었어요.

- [ ] **Q1 거절하면 어디로?** 종료 / W-04로 복귀 / AI 재생성 — 서버 · 팀
- [ ] **Q2 빌드 · 테스트 실패 시** W-03에서 Failed + 실행 종료 + 알림으로 가정 — CI 담당 · 서버
- [ ] **Q3 main merge마다 실행이 하나씩 쌓이는 구조** 가정 — 서버
- [ ] **Q4 merge마다 W-04에서 환경을 고르나, 한 번 고른 환경으로 자동 진행하나** — 팀
- [ ] **Q5 위험 설정을 오류로 보고 AI 수정 루프에 넣나, 경고만 하나** — 서버(김승환)
- [ ] **Q6 재사용(태그만 교체)도 검증을 거치나** — 승인 화면에 plan이 필요해서 거친다고 가정 — 서버(김승환)
- [x] ~~Q7 3회는 환경별인가, 한 환경 실패 시 나머지는?~~ → **환경별, 한 환경이 3회 실패해도 나머지는 계속** (9/29 `server/AGENTS.md`). W-05b의 "AWS 빼고 계속" 버튼은 자동 진행에 맞게 바꿔요
- [ ] **Q8 AI가 Dockerfile도 고치나** — 고치면 W-05 · W-11에 Dockerfile 탭 추가 — 서버(김승환)
- [ ] **Q9 한 환경만 apply 실패 시** 나머지 유지 / 전체 롤백 / 표시만 — 서버 · 팀
- [ ] **Q10 배포 이후 단계(헬스체크 · URL · 롤백)를 흐름에 넣나** — W-08 · W-09 범위 — 팀
- [ ] **업로드 입력(W-02b)을 유지하나** — 유지하면 이미지 빌드 주체와 ADR 추가 필요 — 팀
- [ ] **환경 추가(W-10)를 예선 범위에 넣나** — "왜 AI인가" 후보 (b) — 팀
- [x] ~~`react-router` 추가~~ → 사용 (9/30, 김도영). ADR-006에 기록
- [ ] **로그인 화면** — 와이어프레임에 없어요. R-02 토큰 발급을 쓰는 간단한 로그인 화면이 필요해요 — 웹(디자인 추가)
- [ ] **배포 상태 · 단계 값** 확정 — 웹 · 앱 · 서버가 같은 목록을 써요 (`ios/SPEC.md` §8과 같은 건)
- [x] ~~인증 방식~~ → Bearer 하나 (9/29). 브라우저 SSE 방식만 남음 (WR-01)
- [x] ~~HTTPS 공개 주소~~ → 팀 도메인 HTTPS (9/29 회의, 서버 담당)

`[미정]` 팀 결정 대기: `deploy.yaml` 스키마, 레지스트리, 비밀값 전달 방식, Terraform state 저장소, 검증된 스크립트 저장 위치, LLM · 비용 단가.

---

## 8. 변경 기록

| 날짜 | 변경 | 작성 |
|---|---|---|
| 9/30 | 초안 작성: 와이어프레임 v1.0 · 디자인 시스템 확정본 기준, 백엔드 신규 요구 WR-01~14 | 김도영 |
| 9/30 | 일정: 와이어프레임 화면 전부 10/2까지. `react-router` 사용, Node 22 LTS · pnpm 9 확정 | 김도영 |
