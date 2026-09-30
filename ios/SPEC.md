# SPEC.md — Daisy Apple 앱 (iOS · macOS) 명세와 백엔드 요구사항

> 작성: 박승준 · 상태: **초안 (9/29)** · 참조: 루트 `AGENTS.md`, 노션 ADR-007, Backend API Endpoint 초안 v0.1(김도영), User Flow Chart
> **§6의 API 경로·이벤트 이름은 9/29에 서버(하은현)가 확정했어요** ([#1 리뷰](https://github.com/Softbank-Hackathon-2026-Team-Daisy/daisy/pull/1)). 아직 정해지지 않은 것만 `(가칭)`이나 ❓로 남겨 뒀어요: §6-7 모델 필드 일부, 배포 상태·단계 값, §7 CI 요구사항.
>
> **백엔드 파트(하은현, 김승환)는 [§6 백엔드 요구사항](#6-백엔드-요구사항)부터 읽으면 돼요.** 확정 상태와 제공 일정은 §6-0에 정리했어요.
> CI 파트(김도영)는 [§7](#7-ci-요구사항-가칭--김도영)만 보면 돼요.

---

## 1. 무엇을 만드나요

**Daisy 배포 현황을 휴대폰과 맥에서 보는 네이티브 앱**이에요.

같은 이미지(커밋 해시)가 **어느 환경에, 어느 버전으로** 떠 있는지, 그 버전이 **어떤 커밋과 파이프라인**에서 왔는지, 지금 **어떤 배포가 진행 중이고 무엇을 승인해야 하는지**를 한 앱에서 봐요.

| 질문 | 앱이 답하는 화면 |
|---|---|
| 지금 어느 환경에 뭐가 떠 있지? 전부 같은 버전이야? | 현황 |
| 방금 시작한 배포, 어디까지 갔어? AI가 몇 번 고쳤어? | 배포 상세 |
| 내가 승인해야 할 plan이 있어? 삭제되는 리소스는? | 승인 |
| 이 커밋은 빌드됐어? 어느 환경까지 나갔어? | 커밋·파이프라인 |

### 1-1. 웹과의 역할 분리

웹과 앱은 코드를 공유하지 않고 **같은 백엔드 API만** 써요. 화면을 두 번 만들지 않도록 역할을 나눠요.

> ⚠️ **9/30 변경 (박승준):** 앱도 웹 와이어프레임 v1.0의 화면 · 문구 · 버튼을 모두 가져가요 (W-00 ~ W-13, L-01 ~ L-03). 그래서 앱에서도 저장소 연결, 환경 선택, 배포 시작, 롤백, 연결 테스트, 프로젝트 연결 해제를 할 수 있어요.
> 이건 ADR-007("앱은 승인 · 진행 상태 · 알림만"), 도영 님 메모("W-02~W-04, W-10~W-13, L-xx는 웹 전용"), **`web/SPEC.md` §1-1(PR #9, "웹만 하는 것: 저장소 연결 · 환경 선택 · 배포 시작 · W-10~W-13")**과 **어긋나요.** 팀 결정이라 **9/30 21시 회의에서 확정**해야 해요 (§8). 확정 전까지 앱 쪽은 이 방향으로 만들어 두고, 결정이 반대로 나면 해당 버튼만 빼요.
> 서버에 새로 부탁하는 건 거의 없어요: 웹이 요청해 서버가 받아 준 `WR-xx`를 그대로 써요 (§6-8).

| | 웹 (React) | 앱 (Swift) |
|---|---|---|
| 저장소 연결, 환경 선택, 배포 시작 (W-02 ~ W-04) | O | **O** (9/30 변경, 회의 확정 필요). 업로드(W-02b)는 둘 다 설계만 |
| 생성 · 검증 진행, 중단 처리 (W-05, W-05b) | O | **O** |
| plan 확인 · 승인 · 거절 (W-06) | O | **O** |
| 배포 진행 · 결과 · 동일성 검증 (W-07, W-08) | O | **O** |
| 배포 이력 · 롤백 (W-09) | O | **O** |
| 환경 · 스크립트 · AI 사용량 · 설정 (W-10 ~ W-13) | O | **O** |
| 푸시 알림 (승인 필요 · 완료 · 실패) | 브라우저 알림 | **O** |

- 앱은 **GitHub, 클라우드, Terraform에 직접 붙지 않아요.** 모든 데이터는 Daisy 백엔드 API를 거쳐요. 토큰을 하나만 관리하고, 웹과 같은 데이터를 보여주기 위해서예요

### 1-2. ADR-007 수정 제안 ❓

현재 ADR-007 초안은 "앱은 승인·진행 상태·알림만"이에요. 아래처럼 넓히는 걸 제안해요.

- 추가: **환경별 현재 버전 현황**, **커밋·파이프라인 이력** (둘 다 읽기 전용), **macOS**
- 이유
  - 핵심 키워드 **이식성**("같은 이미지가 모든 환경에 같은 상태로")을 가장 직접 보여주는 화면이 현황이에요
  - 읽기 전용이라 백엔드 추가 부담은 조회 API 2개(§6-2의 `A-02`, `A-06`)예요
  - SwiftUI 멀티플랫폼 한 타깃이라 macOS 추가 비용이 작아요
- 범위를 지키는 장치: 앱에서 배포 시작·설정 변경은 하지 않아요 (1-1 표)

### 1-3. 데모 목표

- **TestFlight 공개 링크**를 발표 화면에 QR로 띄워서, 심사위원이 발표 중에 설치하고 **실시간 배포 진행을 자기 휴대폰으로 보게** 해요
- 심사위원은 **읽기 전용 데모 계정**으로 들어와요 (승인 버튼은 비활성). 승인은 발표자가 자기 휴대폰으로 시연해요
- 발표 흐름 예: 웹에서 환경 선택 → 발표자 휴대폰에 "승인 필요" 푸시 → 앱에서 승인 → 심사위원 휴대폰에서도 환경 3곳이 병렬로 올라가는 게 보임 → 완료 푸시

---

## 2. 화면 구성

코드 하나로 iPhone · iPad · Mac을 모두 지원하고, **플랫폼이 아니라 화면 폭에 따라** 모양이 바뀌어요. 폭이 700 이상이면(iPad · Mac) 직접 그린 사이드바, 좁으면(iPhone) 아래 탭이에요. 현황 · 배포 상세의 환경 카드는 폰에서는 한 열, 넓은 화면에서는 나란히 보여요.

**디자인 (9/30, 박승준):**
- 재질 · 사이드바 · 움직임은 AfterPlan Mac 앱을 그대로 따라요: 사이드바는 HUD 재질(창 뒤 블렌딩), 본문은 창 뒤가 비치는 재질 한 장, 둘 사이에 선 없음. 선택 틴트는 스프링(0.32, 0.86)으로 미끄러지고 굵기는 즉시 바뀌어요. 사이드바 폭은 끌어서 190–420
- 버튼은 Craft 레퍼런스를 따라요: 화면마다 큰 제목 머리줄, 오른쪽에 동그란 글래스 버튼 · 캡슐 버튼 · 캡슐 세그먼트 (macOS 26 · iOS 26 이상은 Liquid Glass)
- **기능 UX는 웹과 맞춰요.** 같은 기능(플랜 승인, 배포 진행, 멀티 환경 상태, 이력)은 웹과 같은 흐름 · 용어 · 표기(리소스 `+/~/-` 등)를 써요. 웹 코드가 아직 없어서 지금 기준은 노션 User Flow Chart와 도영 님 Figma예요

**메뉴 (웹 사이드바와 같은 구성):** 프로젝트 전환 · 새 배포 · PROJECT(개요 · 배포 · 환경 · 이력 · 스크립트) · ENVIRONMENTS(환경별 상태) · AI 사용량 · 설정 · 연결 상태 · 사용자. 좁은 화면은 같은 메뉴를 탭으로 (다섯 개가 넘으면 시스템 "더 보기").
**배치 규칙:** 웹의 좌표는 참고만 하고, 앱 패턴(큰 제목 머리줄 · 카드 · 폭 따라 바뀌는 그리드 · 넓으면 표 좁으면 목록)으로 다시 놓아요. 버튼은 모두 글래스 양식(원 · 캡슐 · 캡슐 세그먼트)이고, 화면의 핵심 동작 하나만 강조 캡슐이에요.

| 웹 화면 | 앱 화면 | 들어가는 곳 | 필요한 API | 우선순위 |
|---|---|---|---|---|
| W-00 · W-00b 로그인 | `LoginView` | 앱 시작 (로그인 전) | R-02, R-09 (가칭) | M |
| W-01 개요 | `OverviewView` | 메뉴 개요 | A-01, A-02(+`image_digest` WR-09), A-03 | M |
| (웹에 없음) 배포 목록 | `DeploymentsView` | 메뉴 배포 | A-03 | M |
| W-02 애플리케이션 연결 → L-01 (W-02b 업로드는 설계만) | `ConnectAppView` | 프로젝트 전환 › 새 프로젝트 연결 | WR-02, WR-03, A-06 | S |
| W-03 이미지 빌드 | `BuildStage` | L-01 뒤 (배포가 생기기 전, 빌드가 끝나면 W-04로) | A-06 | S |
| W-04 배포할 환경 선택 → L-02 | `TargetSelectView` | 사이드바 새 배포, W-03 다음 | WR-04, WR-05 | M |
| W-05 인프라 코드 생성 · 검증 | `RunView` › `GenerateStage` | 배포 한 건 (apply 전) | A-04, WR-07 | M |
| W-05b 배포를 중단했어요 | `RunView` › `StoppedStage` | 배포 한 건 (`failed`, apply 전에 모두 멈춤) | A-04, A-07, WR-05(다시 시도) | S |
| W-06 변경 사항 확인 후 승인 → L-03 | `PlanApprovalView` | 배포 한 건 (승인 대기), 개요 › 지금 할 일 | A-05 + WR-06, W-01 | M |
| W-07 배포 중 | `RunView` › `ApplyStage` | 배포 한 건 (배포 중) | A-04, A-07 | M |
| W-08 배포 결과 | `RunView` › `ResultStage` | 배포 한 건 (끝) | A-04, A-02(+WR-09), WR-05(다시 시도) | M |
| W-09 배포 이력 | `HistoryView` | 메뉴 이력 | A-03, WR-14 | M |
| W-10 환경 | `EnvironmentsView` | 메뉴 환경 | WR-04, A-10 · A-11 (가칭) | S |
| W-11 스크립트 | `ScriptsView` | 메뉴 스크립트 | WR-10 | S |
| W-12 AI 사용량 | `AIUsageView` | 메뉴 AI 사용량 | WR-11 | S |
| W-13 설정 | `SettingsView` (+ 앱 설정: 서버 주소 · 계정 · 버전) | 메뉴 설정 | A-12 (가칭), WR-03, WR-12, WR-13 | S |
| 푸시 알림 | — | 승인 필요 · 완료 · 실패 | P-01, P-02 | S |

M = 예선 데모 필수, S = 선택

---

## 3. 기술 구성

| 항목 | 선택 | 이유 |
|---|---|---|
| UI | **SwiftUI 멀티플랫폼 단일 타깃** (iPhone · iPad · Mac, 네이티브 macOS) | 코드 하나로 모든 화면. 레이아웃은 화면 폭 기준(탭 ↔ 사이드바, 적응형 그리드), `#if os(...)`는 플랫폼 전용 기능에만 |
| 최소 OS | iOS 18 · macOS 15 | iOS 18의 `Tab` API. 2026년 9월 기준 심사위원 기기는 대부분 이보다 최신이에요 |
| 언어 · 도구 | Swift 6 (strict concurrency), Xcode 27 | |
| 외부 라이브러리 | **없음** (SPM 의존성 0개로 시작) | 웹 ADR-006과 같은 "최소 스택, 막힐 때만 추가" 원칙. 추가하면 이유를 ADR에 기록 |
| 네트워크 | `URLSession` + `async/await` + `Codable` | |
| 실시간 | `URLSession.bytes`로 **SSE를 직접 파싱** + 연결 실패 시 **5초 폴링** 폴백 | 웹과 같은 SSE 엔드포인트·이벤트를 그대로 써서 백엔드가 앱용으로 따로 만들 게 없음 (노션 결정 대기 "Swift 앱 실시간 수신"에 대한 제안) |
| 상태 관리 | 화면별 `@Observable` 스토어 | 앱 규모가 작아 별도 아키텍처 프레임워크는 쓰지 않음 |
| 인증 저장 | Keychain | 토큰을 UserDefaults에 두지 않음 |
| 푸시 | APNs (토큰 기반 `.p8` 키) | 백엔드가 발송 (§6-5) |
| 배포 | Xcode 아카이브 → App Store Connect → **TestFlight 외부 테스트 공개 링크** | |
| 목업 | **쓰지 않아요.** 앱은 항상 실서버 API에 붙어요 | 앱 안에 목업 모드 · 가짜 데이터 경로를 두지 않아요. 화면 레이아웃은 Xcode `#Preview` 안의 샘플 값으로만 잡고, 이 값은 앱 실행 경로에 들어가지 않아요 |

### 3-1. 폴더 구조

```
ios/
├─ AGENTS.md                AI 에이전트 규칙 (이 폴더 전용, 영어)
├─ SPEC.md                  이 문서
├─ Daisy.xcodeproj          앱 이름 Daisy, 번들 ID com.teamdaisy.daisy. 폴더 동기화 방식이라 파일을 추가해도 프로젝트 파일을 고칠 필요가 없어요
├─ Daisy/
│  ├─ App/                  진입점, 루트 화면 (폭 700 이상 사이드바 · 미만 탭), 사이드바, 의존성 조립
│  ├─ Features/             화면 단위 폴더. 각 폴더에 View + Store
│  │  ├─ Overview/          1 현황
│  │  ├─ Deployments/       2 배포 목록 · 3 배포 상세
│  │  ├─ Approvals/         4 승인
│  │  ├─ History/           5 커밋 · 파이프라인
│  │  └─ Settings/          6 설정
│  ├─ Core/
│  │  ├─ API/               APIClient 프로토콜, LiveAPIClient, 엔드포인트 정의, APIError
│  │  ├─ Models/            서버 응답 Codable 모델 (§6-7과 1:1)
│  │  ├─ Realtime/          SSE 클라이언트, 이벤트 디코딩, 폴링 폴백
│  │  ├─ Auth/              토큰 저장 (Keychain)
│  │  └─ Push/              APNs 등록, 알림 탭 → 화면 이동
│  ├─ DesignSystem/         재질, 글래스 버튼 · 세그먼트, 머리줄, 카드, 상태 배지, 환경 아이콘
│  └─ Resources/            에셋, 한국어 문자열
├─ DaisyTests/              모델 디코딩 · SSE 파서 · 스토어 테스트 (Swift Testing)
└─ DaisyWidgets/            (S) 위젯 · Live Activity
```

### 3-2. 데이터 흐름

```
View ──▶ Store(@Observable) ──▶ APIClient ──────────▶ Daisy 백엔드 (REST)
  ▲            │ ◀── Realtime(SSE → 이벤트) ◀─────── Daisy 백엔드 (SSE)
  └── 상태 ────┘
```

- 화면은 `APIClient`를 거쳐서만 서버와 통신해요. 서버 주소는 설정에서 바꿔요 (개발 서버 · 데모 서버)
- 실시간 이벤트는 스토어가 받아 상태를 갱신해요. 연결이 끊기면 `Last-Event-ID`로 재연결하고, `resync`가 오면 스냅샷을 다시 조회해요

---

## 4. 경계: 누가 무엇을 하나요

| 영역 | 앱 (박승준) | 백엔드 (하은현 · 김승환) | CI (김도영) |
|---|---|---|---|
| 데이터 원천 | 표시만 | 저장 · 가공 · 제공 | 빌드 이벤트 전송 |
| 배포 상태 | 구독 · 표시 | 상태 머신, SSE 발행 | — |
| 승인 | 버튼 · 확인 문구 입력 | 권한 · 상태 검증 · 멱등 처리 | — |
| 커밋 · 파이프라인 이력 | 표시 | webhook 수신 내용 저장 · 조회 API | payload에 커밋 정보 추가 (§7) |
| 푸시 | 기기 토큰 등록 · 알림 표시 | 기기 토큰 저장 · APNs 발송 | — |
| APNs 키 · Apple 계정 | 발급 · 관리 | 키를 받아 서버 비밀값으로 보관 | — |
| TestFlight | 빌드 · 제출 · 공개 링크 | 심사용 데모 계정 제공 (§6-1) | — |

**앱이 하지 않는 것:** GitHub API 직접 호출, 클라우드 API 직접 호출, Terraform 실행, 배포 시작, 대상 환경 등록·삭제.

---

## 5. 일정 (내 기준)

| 날짜 | 앱 | 백엔드에 필요한 시점 |
|---|---|---|
| D1 (9/29~30) | Xcode 프로젝트 생성, App Store Connect 앱 등록, 현황 · 배포 상세 화면 레이아웃, API 클라이언트 · 모델 | 이 문서 리뷰 → 이름 확정 ✅ (9/29) |
| D2 (10/1) | 로그인, 현황 · 배포 상세를 실서버에 연결 (5초 폴링), 승인 · 커밋 이력 화면 레이아웃. **TestFlight 외부 테스트 첫 빌드 심사 제출** (로그인 · 현황 · 배포 상세 기준) | 인증 R-01·R-02, 데모 계정 R-03, **A-01·A-02·A-04**, 개발 서버 R-08 (은현 님 약속) |
| D3 (10/2) | 배포 목록 · 승인 · 커밋 이력 연결, 폴링 → SSE 전환, 로컬 알림, 전체 흐름 리허설, 공개 링크 QR 준비. D3 기능을 넣은 빌드를 오전에 업로드 | A-03·A-05·A-06·A-07, SSE, 승인 W-01, (여유 있으면) 푸시 |
| 10/3 | 공개 링크 배포 | — |

- **TestFlight 외부 테스트는 첫 빌드에 Beta App Review가 필요해요.** 보통 하루 안팎이지만 보장되지 않아서 **10/1에 제출**하는 게 목표예요. 이후 빌드는 심사가 짧거나 생략되는 경우가 많지만 이것도 보장되지 않아요
- **업로드 전에 필요한 것 (박승준):** App Store Connect에 번들 ID `com.teamdaisy.daisy`로 앱 등록, Xcode에 Development Team 지정. 앱 아이콘은 9/30에 넣었어요 (데이지 로고). 받은 원본이 200×200이라 1024에서 조금 흐려서, **1024 이상 원본(또는 SVG)으로 바꿔야 해요**
- 앱은 로그인이 필요해서 심사 때 **Apple 심사자용 계정**을 적어 내야 해요. 그래서 데모 계정(§6-1 `R-03`)과 HTTPS 서버(`R-04`)가 **D2까지 꼭 필요해요.** 데모 계정은 D2 약속을 받았고, HTTPS는 9/29 회의에서 도메인을 사서 적용하기로 했어요 (서버 담당, 9/30 오후 전)
- 승인 · 커밋 이력은 서버 API가 D3에 나와서, 첫 심사 빌드에는 레이아웃만 들어가요. 심사를 통과한 뒤 올리는 빌드는 다시 심사받지 않는 경우가 많지만 보장되지 않아서, D3 빌드를 오전에 올려요
- 앱에 목업이 없어서 **앱 진행 속도가 백엔드 API 일정에 직접 묶여요.** API가 늦어지면 그 화면은 레이아웃만 먼저 만들고 기다려요

---

## 6. 백엔드 요구사항

- 우선순위: **M** = 앱 데모 필수 · **S** = 있으면 좋음
- "v0.1과 같음"은 노션 Backend API Endpoint 초안 v0.1에 이미 있는 것이에요. 앱 때문에 **새로 필요한 건 🆕**로 표시했어요
- 경로 · 이벤트 이름은 9/29에 서버가 확정했어요. 바뀐 건 P-01 해제 방식 하나예요. 서버의 단일 원천은 OpenAPI 문서이고, 노션 「Backend API Endpoint」는 은현 님이 확정본으로 이어서 고쳐요

### 6-0. 서버 답변 요약 (9/29, 하은현)

| ID | 상태 | 제공 |
|---|---|---|
| R-01 인증 | ✅ Bearer 하나로 통일 (REST · SSE). 쿠키는 받지 않아요 | D2 |
| R-02 토큰 발급 · R-03 데모 계정 · R-08 개발 서버 | ✅ 확정. viewer는 승인 시 403 | D2 |
| R-04 HTTPS 공개 주소 | ✅ 9/29 회의 결정: **도메인을 사서 HTTPS 적용** (하은현 · 김승환) | 9/30 오후 |
| R-05~R-07 공통 규칙 | ✅ v0.1 그대로 | — |
| A-01 · A-02 · A-04 | ✅ 확정. A-02는 `GET /projects/{id}`에 합치지 않고 별도 엔드포인트 | **D2** |
| A-03 · A-05 · A-06 · A-07 | ✅ 확정 | D3 |
| A-08 | 대신 A-03의 `awaiting_approval` 필터를 써요 | — |
| E-01 · E-02 SSE | ✅ 채널 · 이벤트 이름 확정. **D2는 A-04 · A-02 5초 폴링**, D3에 SSE로 바꿔요 | D3 |
| W-01 승인 | ✅ 확정 | D3 |
| P-01 · P-02 푸시 | ✅ 경로 확정, 해제는 `DELETE /devices` + 본문. 배포 흐름이 다 돈 뒤 여유 있으면 해요. 그전까지 앱은 로컬 알림 | 여유 시 |
| §7 CI 요구사항 | 은현 님이 웹훅 수신 쪽 요구로 정리해서 도영 님께 이슈로 전달 | — |
| SSE 녹화 | 첫 실제 배포가 성공하면 은현 님이 텍스트로 전달 | D3 |

### 6-1. 공통

| ID | 요구사항 | 우선 | 비고 |
|---|---|---|---|
| R-01 🆕 | **Bearer 토큰 인증.** `Authorization: Bearer <token>` 헤더를 REST와 SSE 모두에서 받기 | M | 서버는 Bearer 하나로 통일 (쿠키 안 받음). 웹 `EventSource`가 헤더를 못 붙이는 문제는 서버 · 웹이 따로 풀어요 |
| R-02 🆕 | 토큰 발급 `POST /auth/token` `{ username, password }` → `{ access_token, expires_at, role }` | M | 팀 내부 도구라 단순해도 돼요. 가입 기능은 필요 없어요 |
| R-03 🆕 | **읽기 전용 데모 계정** (`role: "viewer"`). 조회 · SSE는 되고 승인은 403 | M | 심사위원 설치용 + TestFlight 심사용. 승인 API가 viewer를 막아야 해요 |
| R-04 🆕 | **HTTPS 공개 주소** | M | 도메인 구매 + HTTPS로 결정 (9/29 회의). iOS는 기본적으로 HTTP 연결을 막아요(ATS). 발표장에서 심사위원 휴대폰(LTE)이 접속할 수 있어야 해요 |
| R-05 | 공통 규칙은 v0.1과 같음: 시간 ISO 8601 UTC, 에러 `{ error: { code, message, details, retryable } }`, 목록 `{ items, next_cursor }`, ID 접두사, 승인 POST에 `Idempotency-Key` | M | |
| R-06 | JSON 키는 `snake_case` 그대로 좋아요 | — | 앱에서 변환해요 |
| R-07 | 상태 같은 enum 값은 **문자열**. 새 값을 추가해도 앱은 "알 수 없음"으로 표시하고 죽지 않아요 | — | 안심하고 추가해도 돼요 |
| R-08 🆕 | **개발 서버 주소를 D1~D2에 공유** (HTTPS, 실제 데이터 조금이라도) | M | 앱에 목업이 없어서 개발 서버가 있어야 화면을 연결할 수 있어요. 완성 전이라도 M 조회 API부터 열어 주세요 |

### 6-2. 조회 API

| ID | 메서드 · 경로 | 쓰는 화면 | 응답 요약 | 우선 | 비고 |
|---|---|---|---|---|---|
| A-01 | `GET /projects` | 현황 (프로젝트 선택) | `Project[]` | M | v0.1 제안과 같음 |
| A-02 🆕 | `GET /projects/{id}/targets/status` | **현황** | 환경별 현재 상태 `TargetStatus[]` (§6-7) | M | 앱이 자주 부르는 화면이라 별도 엔드포인트로 둬요. **앱의 핵심 화면.** 앱은 목록 공통 봉투 `{ items, next_cursor }`로 받는다고 가정했어요 `(가칭)` |
| A-03 | `GET /projects/{id}/deployments?state=&cursor=` | 배포 목록 | `Deployment` 요약 목록 | M | v0.1 제안과 같음 |
| A-04 | `GET /deployments/{id}` | 배포 상세 | `Deployment` 스냅샷 | M | v0.1과 같음. 환경별 `attempt`와 현재 단계 포함. 한 환경이 3회 실패해도 다른 환경은 계속 진행해요. **`attempt`는 첫 생성을 포함한 총 시도 횟수**예요: `1/3`부터 시작하고 AI 수정은 최대 2번. 화면 문구는 "시도 n/3" |
| A-05 | `GET /deployments/{id}/plan` | 승인 | `Plan` (환경별 개수 · 삭제 여부 · 위험 설정) + `ai_usage` | M | 서버의 `PlanSummary`(김승환) 그대로. AI 토큰 · 비용은 plan 안이 아니라 응답의 `ai_usage` 합계로 같이 와요. 원화 비용은 **고정 환율로 환산한 추정치**라, 앱은 "추정"과 적용 환율을 같이 보여줘요. 앱은 **요약 필드만** 써요 (리소스 전체 목록은 웹) |
| A-06 🆕 | `GET /projects/{id}/builds?cursor=` | **커밋 · 파이프라인** | `Build[]` (§6-7) | M | Actions webhook으로 받은 내용을 저장해 두고 돌려주면 돼요. 커밋별 **배포된 환경 목록**까지 |
| A-07 🆕 | `GET /deployments/{id}/logs?target_id=&tail=100` | 배포 상세 | 최근 로그 N줄 | S | SSE가 끊겼다 들어왔을 때 최근 로그 채우기용 |
| A-08 | `GET /approvals?state=pending` | 승인 탭 배지 | 대기 중 승인 목록 | S | 만들지 않아요. A-03의 `awaiting_approval` 필터로 대신해요 (9/29 합의) |

### 6-3. 실시간 (SSE)

v0.1의 SSE 채널·봉투·재연결 규칙을 **그대로** 써요. 앱에 필요한 건 아래 이벤트만이에요.

| ID | 채널 | 이벤트 | 앱 반응 | 우선 |
|---|---|---|---|---|
| E-01 | `GET /deployments/{id}/events` | `deployment.state_changed` | 상단 상태 | M |
| | | `step.started` · `step.completed` · `step.failed` (`target_id`, `step`, **`attempt`**, `error?`) | 환경별 단계 · "시도 n/3" | M |
| | | `plan.ready` · `approval.required` · `approval.resolved` | 승인 카드 표시 · 닫기 | M |
| | | `deployment.completed` (환경별 URL) | 완료 · URL | M |
| | | `heartbeat` · `resync` | 연결 상태 · 스냅샷 재조회 | M |
| | | `log.batch` | 최근 로그 | S |
| E-02 | `GET /projects/{id}/events` | `target.status_changed` | 현황 카드 갱신 | M |
| | | 🆕 `deployment.created` | 새 배포를 목록 맨 위에 추가 | S |
| | | 🆕 `build.received` (새 이미지 도착) | 커밋 이력 갱신 | S |

- SSE도 Bearer 헤더(R-01)로 인증해요
- `Last-Event-ID` 재연결은 v0.1 4-5 그대로예요. 서버가 DB의 `seq`로 재생해서 이벤트 보관 기간은 신경 쓰지 않아도 돼요
- **D2는 SSE 대신** 앱이 `A-04` · `A-02`를 5초마다 폴링해요. D3에 SSE로 바꿔요
- **녹화:** 첫 실제 배포가 성공하면 은현 님이 이벤트를 텍스트로 전달해요. SSE 파서 테스트에 써요

### 6-4. 쓰기 API

| ID | 메서드 · 경로 | 요청 | 우선 | 비고 |
|---|---|---|---|---|
| W-01 | `POST /deployments/{id}/approvals` | `{ kind: "plan", decision: "approve" \| "reject", comment?, confirm_text? }` + `Idempotency-Key` | M | v0.1 3-3과 같음. 앱은 `kind: "plan"`만 써요 |

- 웹에서 먼저 승인했으면 **409 `STATE_CONFLICT`**를 주세요. 앱은 최신 상태를 다시 불러와요
- 삭제가 포함된 plan은 `confirm_text`를 서버에서도 검증해 주세요 (v0.1과 같음)
- ❓ **`confirm_text`에 무엇을 넣나요?** v0.1 예시는 대상 환경 이름(`gcp-prod`)인데, 환경이 여러 개면 어떻게 하는지 정해 주세요. 지금 앱은 사용자가 입력한 값을 그대로 보내요 `(가칭)`
- viewer 역할이면 **403** (R-03)
- **plan을 다시 뜨는 경우 (9/29, 하은현):** 승인 대기가 길어져 plan이 낡으면(stale) 서버가 plan을 다시 뜨고 이전 승인은 무효가 돼요. 이건 AI 수정이 아니라서 **`attempt`는 그대로**이고, `approval.required`가 다시 와요. 앱은 같은 "시도 n/3"으로 승인 카드를 다시 띄우고, "plan이 갱신됐어요"처럼 이유를 보여줘요
- ❓ **승인 단위**: 배포 전체를 한 번에 승인하나요, 환경별로 따로 승인하나요? 플로우차트(7-1~7-3)는 전체 한 번으로 읽혀요. 앱은 둘 다 그릴 수 있지만 확정이 필요해요

### 6-5. 푸시 알림 (S, 데모 효과 큼)

| ID | 요구사항 | 비고 |
|---|---|---|
| P-01 🆕 | 기기 토큰 등록 `POST /devices` `{ apns_token, platform: "ios" \| "macos", apns_env: "production" \| "sandbox" }` · 해제 **`DELETE /devices` + 본문 `{ apns_token }`** | 로그인한 사용자와 묶어서 저장. 토큰을 URL 경로에 넣으면 서버 · 프록시 로그에 남아서 본문으로 보내요 (9/29 합의) |
| P-02 🆕 | 백엔드가 APNs로 발송: **승인 필요** · **배포 완료** · **배포 실패**(최초 생성 포함 총 3회 시도 후 실패 포함) | payload: `aps.alert` + `{ kind, project_id, deployment_id }`. 앱은 이 값으로 화면을 열어요 |
| P-03 | APNs 인증 키(`.p8`), Key ID, Team ID는 **박승준이 발급해서 비밀값으로 전달** | 커밋 금지. 전달 방식은 팀 비밀값 저장소 `[미정]` |

- **TestFlight 빌드는 `production` APNs 서버**로 보내야 해요. Xcode에서 바로 설치한 개발 빌드만 `sandbox`예요. 그래서 등록할 때 `apns_env`를 같이 보내요
- **D3까지는 로컬 알림**이에요: 앱이 켜져 있는 동안 받은 이벤트로 알림을 띄워요 (백엔드 작업 0). APNs는 배포 흐름이 다 돈 뒤 여유 있으면 해요 (9/29 합의)
- 언어별 APNs 라이브러리 예: Node `apns2`, Spring `pushy`, Python `aioapns` — 백엔드 언어가 정해지면 골라 주세요

### 6-6. 백엔드가 가진 정보 중 앱이 꼭 받아야 하는 것

API 모양보다 **이 정보가 어딘가에 저장되어 있는지**가 더 중요해요. 이름은 자유롭게 정해 주세요.

- 환경별 **지금 떠 있는 커밋 해시 · 이미지 · 배포 시각 · 공개 URL · 헬스**
- 배포별 **환경마다의 현재 단계, 최초 생성 포함 총 시도 횟수(n/3), 실패 이유 한 줄**
- plan별 **환경마다의 생성 · 변경 · 삭제 개수, 삭제 포함 여부, 위험 설정 목록** + AI 토큰 · 비용(`ai_usage` 합계)
- 빌드(커밋)별 **메시지 · 작성자 · 시각 · Actions 결과 · 실행 링크 · 이미지 태그 · 배포된 환경**

### 6-7. 데이터 모델

앱의 `Core/Models`와 1:1로 맞출 모양이에요. `Plan`은 서버의 `PlanSummary` 기준이에요. 나머지 필드 이름은 서버 OpenAPI가 나오면 맞추고, 그때까지는 `(가칭)`이에요.

```jsonc
// Project
{ "id": "prj_1", "name": "hellocalc", "repository": "Softbank-Hackathon-2026-Team-Daisy/sample-monolith" }

// TargetStatus — A-02, 현황 화면
{
  "target_id": "tgt_gcp",
  "type": "onprem" | "aws" | "gcp",
  "name": "gcp-prod",
  "current": {                              // 한 번도 배포 안 됐으면 null
    "commit": "2311c0b683ec0f46d0be1c640591245ae8d1c093",
    "image": "ghcr.io/softbank-hackathon-2026-team-daisy/sample-monolith:2311c0b…",
    "deployment_id": "dep_42",
    "deployed_at": "2026-10-03T10:12:05Z"
  },
  "url": "https://hellocalc-xxxx.a.run.app",
  "health": "healthy" | "unhealthy" | "unknown",
  "checked_at": "2026-10-03T10:13:00Z"
}

// Deployment — A-03 목록(요약), A-04 스냅샷(전체)
{
  "id": "dep_42",
  "project_id": "prj_1",
  "commit": "2311c0b…",
  "image": "ghcr.io/…:2311c0b…",
  "state": "queued" | "running" | "awaiting_approval"
         | "succeeded" | "partially_succeeded" | "failed" | "cancelled",   // 9/30 서버 확정 (배포 전체)
  "kind": "rollback" | null,               // 롤백은 상태가 아니라 별도 배포 (WR-14)
  "rolled_back_from": "dep_41" | null,
  "targets": [
    {
      "target_id": "tgt_gcp",
      "state": "waiting" | "generating" | "validating" | "awaiting_approval"
             | "applying" | "verifying" | "succeeded" | "failed" | "cancelled",   // 9/30 서버 확정 (환경별)
      "step": "generate" | "validate" | "plan" | "risk_check" | "apply" | "health_check",
      "step_state": "running" | "done" | "failed" | "waiting",
      "attempt": 1,                          // 첫 생성을 포함한 총 시도 횟수 (1~3). 화면에는 "시도 n/3"
      "reused_script": false,                // 검증된 스크립트 재사용 (AI 호출 0회)이면 true
      "url": null,
      "error_summary": null
    }
  ],
  "pending_approval": { "approval_id": "apv_7", "kind": "plan" } | null,
  "created_by": "도영",
  "created_at": "…",
  "finished_at": null,
  "last_seq": 1042
}

// Plan — A-05, 승인 화면
{
  "deployment_id": "dep_42",
  "targets": [
    {
      "target_id": "tgt_aws",
      "counts": { "create": 12, "update": 0, "delete": 0 },
      "has_delete": false,                  // 리소스 교체(replace)로 삭제가 생겨도 true
      "risks": [ { "level": "high", "rule": "sg-open-world", "resource": "aws_security_group.web", "message": "보안 그룹이 0.0.0.0/0에 열려 있어요" } ]
    }
  ],
  "ai_usage": { "tokens": 18234, "cost_krw": 312, "exchange_rate": 1400, "estimated": true }
  // (가칭) 누적 합계. 서버는 USD로 합산한 뒤 고정 환율로 원화 환산해요. 필드 모양은 서버 OpenAPI 기준으로 맞춰요
}

// Build — A-06, 커밋·파이프라인 화면
{
  "commit": "2311c0b…",
  "message": "feat(ci): Daisy 앱 연결 요구사항 추가",
  "author": "Seungjun1127",
  "committed_at": "…",
  "pipeline": { "status": "running" | "success" | "failed", "run_url": "https://github.com/…/actions/runs/…" },
  "image": "ghcr.io/…:2311c0b…" | null,     // 실패하면 null
  "deployed_to": [ { "target_id": "tgt_gcp", "deployment_id": "dep_42", "deployed_at": "…" } ]
}
```

---

### 6-8. 와이어프레임 화면에 쓰는 API — 9/30 저녁 최신화

앱이 웹 화면을 모두 가져가면서 필요한 API예요. **웹이 먼저 요청해 서버가 답한 `WR-xx`(`web/SPEC.md` §6-1, PR #9 은현 님 답변)를 그대로 써요.** 경로 · 모양도 웹 문서를 따라요. 앱 코드는 `Core/API/WebEndpoints.swift`, `Core/Models/WebModels.swift`에 있어요.

**웹과 같이 쓰는 것 (서버 답변 있음)**

| ID | 메서드 · 경로 | 앱 화면 | 서버 답변 (9/30) |
|---|---|---|---|
| WR-02 | `POST /projects` `{ repository, branch }` | W-02 연결하기 | 좋아요, 응답에 deploy.yaml 검증 결과 · D2 |
| WR-03 | `GET /projects/{id}/manifest` | W-02 배포 명세 확인 · W-13 | 좋아요, 모양은 `deploy.yaml` 스키마 결정 뒤 · D3 |
| WR-04 | `GET /projects/{id}/targets` → `target_id, type, name, reuse{ available, script_id?, reason? }, connection{ state: ok·failed·unknown, checked_at }` | W-04 · W-10 · 사이드바 | 별도 엔드포인트로 · D2 |
| WR-05 | `POST /projects/{id}/deployments` `{ commit, target_ids[] }` + `Idempotency-Key` | W-04 시작, **W-05b "처음부터 다시 시도" · W-08 "다시 시도"도 같은 커밋으로 새 배포** | 이 경로로 확정 · D2 |
| WR-06 | `GET /deployments/{id}/plan?detail=resources` | W-06 리소스 행 (`action`에 `replace` 포함) | 좋아요 · D3 |
| WR-07 | `GET /deployments/{id}/targets/{target_id}/script` → `files[{ path, content }]` | W-05 생성된 스크립트 | 18시 백엔드 회의에서 확인 |
| WR-08 | `POST /deployments/{id}/cancel` | (앱은 아직 버튼 없음) | 좋아요 · D3 |
| WR-09 | A-02에 `image_digest` | W-01 · W-08 동일성 검증 (앱이 digest · 커밋 · 헬스로 표를 만들어요. **예전 A-09 요청은 뺐어요**) | 넣을게요 · D2 |
| WR-10 | `GET /projects/{id}/scripts` | W-11 | 승환 님 영역, D3~ |
| WR-11 | `GET /projects/{id}/ai-usage` → `summary{…}, items[{ at, target_id, step: generate·fix, attempt, tokens, cost_krw, status }]` | W-12 | 좋아요, 환율 숫자만 미정 · D3 |
| WR-12 | `PUT /projects/{id}/secrets/{name}` | W-13 비밀값 추가 (지금은 비활성) | 전달 방식 팀 결정 대기 |
| WR-13 | `DELETE /projects/{id}` | W-13 연결 해제 (확인 입력은 화면에서) | 좋아요 · S |
| WR-14 | `POST /deployments/{id}/rollback` `{ target_ids[], reason }` → `Deployment(kind: "rollback")` | W-09 롤백 → 새 배포로 이동, **plan 승인을 거쳐요** | 넣을게요 (은현 님) |

**앱이 더 부탁하는 것 (가칭) 🆕** — 웹 W-10 · W-13 · W-00에도 같은 버튼이 있어요. 받으실지는 서버가 정해 주세요 (이슈로 전달)

| ID | 메서드 · 경로 (가칭) | 앱 화면 | 요약 |
|---|---|---|---|
| R-09 | `POST /auth/demo` → `AuthToken(role: "viewer")` | W-00 "데모 계정으로 둘러보기 (읽기 전용)" | 심사위원이 비밀번호 없이 들어오는 버튼. **인증 범위는 9/30 회의 안건**이라 결정 뒤 맞춰요. `/auth/token` + 공개 데모 계정으로 대신해도 돼요 |
| A-10 | `POST /targets/{id}/test` → `{ connected, message }` | W-10 "연결 테스트" | WR-04 `connection`을 지금 다시 확인 |
| A-11 | `GET /targets/{id}/resources` → `[{ address, type }]` | W-10 "리소스 보기" | 이 환경 state에 있는 리소스 |
| A-12 | `GET /projects/{id}` → `id, name, repository, branch, build?, registry?, webhook_last_at?` | W-13 저장소 카드 | 노션 계약 v0.2 §3-2 제안과 같아요 |

**기존 모델에 더한 필드 (가칭) 🆕** — 없으면 화면이 "—"나 기본 문구로 보여줘요. 필수는 아니에요.

- `Deployment`: `version`("v7"), `commit_message`
- `Deployment.targets[]`: `title`("home-lab · Docker"), `steps[]`(`{ name, state, duration_ms, started_at }`, W-05 검증 단계 · W-07 레인), `health_summary`("200 OK · p95 120ms")
- `Plan.targets[]`: `reused_script`
- `Build`: `branch`, `digest`, `steps[]` (W-03 GitHub Actions 단계)
- `Project`: `branch`
- WR-04 `Target`: W-10 줄 `title, runtime, location, access_method, exposure, state_backend, current_commit`
- WR-10 `Script`: W-11 정보 카드 `note, base_commit, input, ai_tokens, storage, created_at`
- WR-03 `Manifest`: `raw`(원문), `ref`("deploy.yaml · main@a1b2c3d")

**9/30 저녁에 뺀 것:** A-09 동일성 검증 API(→ WR-09), B-01 저장소 미리 확인(→ WR-02 응답 + WR-03), B-03 · B-04 업로드(범위 밖), B-09 · B-11 재시도 API(→ WR-05 새 배포), B-10 "○○ 빼고 계속"(Q7: 나머지 환경은 자동으로 계속), 상태 `building` · `selecting_targets` · `stopped`(W-03 · W-04는 배포가 생기기 전 화면), 인프라 월 비용(서버 보류, 오면 보여줘요)

## 7. CI 요구사항 (가칭) — 김도영

커밋 · 파이프라인 화면(A-06)을 채우려면 Actions가 보내는 이벤트에 정보가 조금 더 필요해요. 이 payload는 서버 웹훅으로 들어가서, **은현 님이 정리해 도영 님께 이슈로 전달**하기로 했어요 (9/29). 현재 `sample-monolith/.github/workflows/ci.yml`의 `notify` 잡 기준이에요.

| ID | 요구사항 | 우선 | 비고 |
|---|---|---|---|
| C-01 🆕 | payload에 `commit_message`, `author`, `committed_at` 추가 | M | `github.event.head_commit`에 있어요. 없으면 백엔드가 GitHub API로 따로 가져와야 해요 |
| C-02 🆕 | **실패해도 이벤트 전송** (`status: "failed"`) | S | 지금은 `image` 잡이 성공해야만 `notify`가 돌아요. `if: always()` + 결과값 전달 |
| C-03 🆕 | 파이프라인 시작 시 `status: "running"` 이벤트 | S | 커밋 화면에서 "빌드 중" 표시 |

---

## 8. 결정이 필요한 것 ❓

- [ ] **ADR-007 범위 수정** (§1-2): 현황 · 커밋 이력 · macOS 추가 — 9/29 회의
- [x] ~~Bearer 토큰 병행~~ → Bearer 하나로 통일 (9/29, 은현 님)
- [x] ~~개발 서버 · 데모 계정 준비~~ → D2 은현 님 (9/29)
- [x] ~~HTTPS 공개 주소 (R-04)~~ → 도메인 구매 + HTTPS (9/29 회의, 서버 담당)
- [ ] **승인 단위**: 배포 전체 한 번 / 환경별 (§6-4)
- [ ] **`confirm_text` 값** (§6-4)
- [ ] **앱 범위를 웹 전체로 넓힐지** (§1-1 ⚠️): ADR-007 · 도영 님 메모 · `web/SPEC.md` §1-1과 어긋나요 — **9/30 21시 회의**
- [ ] **§6-8 앱 추가 요청 R-09 · A-10 ~ A-12 · 필드 추가**를 서버가 받을지 — 하은현 · 김승환 (이슈로 전달)
- [ ] **데모 계정 진입 방식** (R-09): 인증 범위 회의에서 — 팀
- [ ] **Q4 빌드가 끝나면 W-04로 바로 갈지** — 앱은 지금 바로 넘어가요. 팀 결정에 맞춰요
- [ ] **헬스체크 실패 시 자동 롤백** (은현 님 제안): 넣으면 이력에 롤백 배포가 승인 없이 생겨요. 앱은 `kind: "rollback"`으로 표시만 해요 — 팀
- [x] ~~배포 상태 · 단계 값~~ → 9/30 서버 확정 (§6-7): 배포 전체 `queued · running · awaiting_approval · succeeded · partially_succeeded · failed · cancelled`, 환경별 `waiting · generating · validating · awaiting_approval · applying · verifying · succeeded · failed · cancelled`. 롤백은 별도 배포
- [x] ~~Q7 한 환경 3회 실패 시~~ → 환경별, 나머지는 계속 (9/29 서버). W-05b "빼고 계속" 버튼 뺌
- [x] ~~업로드 입력(W-02b)~~ → 서버 작업 없음, 앱은 설계만 표시 (9/30 은현 님 답변. 웹 화면 처리는 도영 님 결정)
- [x] ~~푸시를 예선 범위에 넣을지~~ → D3까지 로컬 알림, APNs는 여유 있으면 (9/29)
- [x] ~~경로 · 이벤트 이름 확정~~ → 9/29 확정. 모델 필드는 서버 OpenAPI가 나오면 맞춰요

---

## 9. 변경 기록

| 날짜 | 변경 | 작성 |
|---|---|---|
| 9/29 | 초안 작성 | 박승준 |
| 9/29 | 앱 목업 모드 제거 (항상 실서버 연결), 개발 서버 요구(R-08) 추가 | 박승준 |
| 9/29 | 에이전트 규칙 파일을 `CLAUDE.md` → `AGENTS.md`로 변경 | 박승준 |
| 9/29 | 서버 답변 반영: 경로 · 이벤트 이름 확정, Bearer만, `DELETE /devices` + 본문, `attempt` 의미, Plan 모양(`level`·`resource`, `ai_usage`), 제공 일정 D2/D3, 폴링 · 로컬 알림 폴백 | 박승준 |
| 9/30 | 팀 방향에 맞춤: 서버 확정 상태 두 층, 웹 `WR-xx` 경로 · 모양 그대로 사용(배포 시작 `POST /projects/{id}/deployments`, 롤백은 새 배포 + 승인, 동일성은 `image_digest`), Q7 반영("빼고 계속" 제거), 업로드 설계만, W-03 · W-04를 배포 전 화면으로. §6-8을 WR-xx + 앱 추가 요청(R-09, A-10 ~ A-12)으로 다시 씀 | 박승준 |
| 9/30 | 와이어프레임 v1.0 화면 · 문구 · 버튼을 앱에 모두 옮김 (W-00 ~ W-13, L-01 ~ L-03), 메뉴를 웹 사이드바 구성으로, 새 요청 §6-8 (가칭) | 박승준 |
| 9/30 | 웹(Figma 와이어프레임 v1.0) 문구로 통일: 메뉴 개요 · 배포 · 승인 · 이력 · 설정, 상태 이름, `리소스 +6 ~0 −0`, 로그인 · 오류 문구. 색 · 모양은 앱 방식 유지, 아이콘은 비슷한 SF Symbols | 박승준 |
| 9/30 | 앱 아이콘 적용 (iOS 1024 꽉 찬 정사각형, macOS 둥근 사각형 격자 16–1024), 사이드바 머리에 로고 | 박승준 |
| 9/30 | 디자인 적용: AfterPlan 재질 · 사이드바 · 움직임, Craft 버튼(글래스 원 · 캡슐 · 세그먼트), 큰 제목 머리줄, 웹과 기능 UX 맞추기 | 박승준 |
| 9/30 | 반응형으로 변경: 최소 iOS 18 · macOS 15, 탭 ↔ 사이드바 자동 전환, 현황 · 배포 상세 적응형 카드 그리드 | 박승준 |
| 9/30 | 앱 뼈대 구현 후 최신화: A-02 목록 봉투 가정, `confirm_text` 값 질문, TestFlight 업로드 준비물 | 박승준 |
| 9/30 | 리뷰 반영: "총 시도 횟수" 문구(승환 님), plan 재생성 시 재승인 동작(은현 님), AI 비용 추정 · 환율 표시(`server/AGENTS.md`), R-04는 도메인 + HTTPS로 확정(9/29 회의) | 박승준 |
