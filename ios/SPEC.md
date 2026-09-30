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

| | 웹 (React) | 앱 (Swift) |
|---|---|---|
| 저장소 연결, 환경 선택, 배포 시작 | O | X |
| plan 상세 검토 (리소스 전체 목록, 스크립트) | O | 요약만 |
| plan 승인 · 거절 | O | **O** |
| 배포 진행 상태 | O (전체 로그) | **O** (단계 · 최근 로그) |
| 환경별 현재 버전 현황 | O | **O** |
| 커밋 · 파이프라인 이력 | O | **O** |
| 푸시 알림 (승인 필요 · 완료 · 실패) | 브라우저 알림 | **O** |

- 앱은 **보기 + 승인 + 알림**만 해요. 배포를 새로 시작하거나 인프라를 바꾸는 기능은 넣지 않아요 (승인은 예외: 사람 승인은 흐름의 필수 단계라 휴대폰에서 바로 할 수 있게 해요)
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

| # | 화면 | 내용 | 우선순위 |
|---|---|---|---|
| 1 | **현황** | 프로젝트 선택 → 환경 카드(온프레미스 · AWS · GCP): 현재 커밋 해시(앞 7자리), 배포 시각, 헬스, 공개 URL. **모든 환경이 같은 커밋인지** 표시 (다르면 "버전 불일치" 배지) | M |
| 2 | **배포 목록** | 진행 중 / 완료 / 실패. 커밋, 대상 환경, 시작 시각, 결과 | M |
| 3 | **배포 상세** | 환경별 단계 진행 (생성 → validate → plan → 위험 검사 → 승인 대기 → apply → 완료), AI 수정 시도 `n/3`, 최근 로그, 결과 URL. 실시간 갱신 | M |
| 4 | **승인** | 대기 중인 plan: 환경별 생성·변경·삭제 개수, 삭제 포함 경고, 위험 설정 요약, AI 비용. 승인 · 거절. 삭제가 있으면 확인 문구 입력 | M |
| 5 | **커밋 · 파이프라인** | main 커밋 목록: 메시지, 작성자, Actions 결과, 이미지 태그, **이 커밋이 배포된 환경** | M |
| 6 | 설정 | 서버 주소, 로그인 · 로그아웃, 알림 설정 | M |
| 7 | 푸시 알림 | 승인 필요 · 배포 완료 · 배포 실패. 누르면 해당 화면으로 이동 | S |
| 8 | macOS 메뉴 막대 | 메뉴 막대 아이콘에서 환경별 상태 한눈에 보기 (`MenuBarExtra`) | S |
| 9 | 위젯 · Live Activity | 홈 화면 위젯(환경 현황), 잠금 화면 배포 진행 | S (여유 있을 때) |

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
  "state": "queued" | "generating" | "validating" | "awaiting_approval"
         | "applying" | "succeeded" | "failed" | "cancelled",   // ❓ 백엔드 상태 머신에 맞춰 확정
  "targets": [
    {
      "target_id": "tgt_gcp",
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
- [ ] **배포 상태 · 단계 값** 확정 (§6-7 `state`, `step`) — 웹 · 앱 · 백엔드가 같은 목록을 써요
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
| 9/30 | 앱 아이콘 적용 (iOS 1024 꽉 찬 정사각형, macOS 둥근 사각형 격자 16–1024), 사이드바 머리에 로고 | 박승준 |
| 9/30 | 디자인 적용: AfterPlan 재질 · 사이드바 · 움직임, Craft 버튼(글래스 원 · 캡슐 · 세그먼트), 큰 제목 머리줄, 웹과 기능 UX 맞추기 | 박승준 |
| 9/30 | 반응형으로 변경: 최소 iOS 18 · macOS 15, 탭 ↔ 사이드바 자동 전환, 현황 · 배포 상세 적응형 카드 그리드 | 박승준 |
| 9/30 | 앱 뼈대 구현 후 최신화: A-02 목록 봉투 가정, `confirm_text` 값 질문, TestFlight 업로드 준비물 | 박승준 |
| 9/30 | 리뷰 반영: "총 시도 횟수" 문구(승환 님), plan 재생성 시 재승인 동작(은현 님), AI 비용 추정 · 환율 표시(`server/AGENTS.md`), R-04는 도메인 + HTTPS로 확정(9/29 회의) | 박승준 |
