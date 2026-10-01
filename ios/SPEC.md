# SPEC.md — Daisy Apple 앱 (iOS · macOS) 명세와 백엔드 요구사항

> 작성: 박승준 · 상태: **10/1 최신화** (결정 보드 `ios/BOARD.md` · 웹 PR #18 화면 기준) · 참조: 루트 `AGENTS.md`, 노션 ADR-007, 프론트 ↔ 백엔드 계약 초안 v0.3, User Flow Chart
> **서버 · 인프라가 아직 정하지 않아서 앱이 가정으로 두고 있는 것은 [§6-9](#6-9-미정-서버--인프라-결정-대기-101)에 모아 뒀어요.**
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
| 지금 어느 환경에 뭐가 떠 있지? 전부 같은 버전이야? | 개요 (W-01) |
| 방금 시작한 배포, 어디까지 갔어? AI가 몇 번 고쳤어? | 배포 (W-05 ~ W-08) |
| 내가 승인해야 할 plan이 있어? 삭제되는 리소스는? | 배포 › 변경 사항 확인 후 승인 (W-06) |
| 이 커밋은 빌드됐어? 어디까지 나갔어? 되돌릴 수 있어? | 새 배포 › 이미지 빌드 (W-03), 이력 (W-09) |

### 1-1. 웹과의 역할 분리

웹과 앱은 코드를 공유하지 않고 **같은 백엔드 API만** 써요. 화면을 두 번 만들지 않도록 역할을 나눠요.

> ✅ **10/1 확정 — ADR-007: 앱도 웹과 같은 전체 흐름이에요** (팀장 결정, 루트 `AGENTS.md` §12-4, [#33](https://github.com/Softbank-Hackathon-2026-Team-Daisy/daisy/pull/33), `web/SPEC.md` §1-1). 앱도 웹 와이어프레임 v1.0의 화면 · 문구 · 버튼을 모두 가져가요 (W-00 ~ W-13, L-01 ~ L-03): 저장소 연결, 환경 선택, 배포 시작, 승인, 롤백, 연결 테스트, 프로젝트 연결 해제까지.
> **나누는 기준:** 앱은 문구(화면 · 메뉴 이름, 상태 이름, 안내 문구)와 흐름을 웹에서 가져가고, 색 · 모양 · 레이아웃은 앱 디자인을 따라요. 웹에서 문구를 바꾸면 앱도 맞춰요.
> 서버에 새로 부탁하는 건 거의 없어요: 웹이 요청해 서버가 받아 준 `WR-xx`를 그대로 써요 (§6-8).

| | 웹 (React) | 앱 (Swift) |
|---|---|---|
| 저장소 연결, 환경 선택, 배포 시작 (W-02 ~ W-04) | O | **O** (10/1 ADR-007 확정). 업로드(W-02b)는 범위 제외 (9/30, 둘 다 화면 없음) |
| 생성 · 검증 진행, 중단 처리 (W-05, W-05b) | O | **O** |
| plan 확인 · 승인 · 거절 (W-06) | O | **O** |
| 배포 진행 · 결과 · 동일성 검증 (W-07, W-08) | O | **O** |
| 배포 이력 · 롤백 (W-09) | O | **O** |
| 환경 · 스크립트 · AI 사용량 · 설정 (W-10 ~ W-13) | O | **O** |
| 푸시 알림 (승인 필요 · 완료 · 실패) | 브라우저 알림 | **O** |

- 앱은 **GitHub, 클라우드, Terraform에 직접 붙지 않아요.** 모든 데이터는 Daisy 백엔드 API를 거쳐요. 토큰을 하나만 관리하고, 웹과 같은 데이터를 보여주기 위해서예요

### 1-2. ADR-007 ✅ (10/1 확정)

ADR-007 초안("앱은 승인 · 진행 상태 · 알림만")을 넓히자는 제안(9/29 현황 · 커밋 이력 · macOS, 9/30 웹 화면 전체)이 **10/1 팀장 결정으로 "앱도 웹과 같은 전체 흐름"으로 확정**됐어요 (#33). 노션 ADR 페이지 갱신은 팀장이 따로 해요.

- 앱이 iPhone · iPad · Mac을 한 코드로 지원하는 것(macOS 포함)도 그대로예요
- 이식성("같은 이미지가 모든 환경에 같은 상태로")을 보여주는 개요 · 동일성 검증 화면이 앱에도 있어요

### 1-3. 데모 목표

- **TestFlight 공개 링크**를 발표 화면에 QR로 띄워서, 심사위원이 발표 중에 설치하고 **실시간 배포 진행을 자기 휴대폰으로 보게** 해요
- 심사위원은 **읽기 전용 데모 계정**으로 들어와요 (승인 버튼은 비활성). 승인은 발표자가 자기 휴대폰으로 시연해요
- 발표 흐름 예: 웹에서 환경 선택 → 발표자 휴대폰에 "승인 필요" 푸시 → 앱에서 승인 → 심사위원 휴대폰에서도 환경 3곳이 병렬로 올라가는 게 보임 → 완료 푸시

---

## 2. 화면 구성

코드 하나로 iPhone · iPad · Mac을 모두 지원하고, **플랫폼이 아니라 화면 폭에 따라** 모양이 바뀌어요. 폭이 700 이상이면(iPad · Mac) 직접 그린 사이드바, 좁으면(iPhone) 아래 **얇은 글래스 캡슐 탭 바**예요 (글씨 없이 SF Symbols만, 일곱 메뉴가 한 줄, 승인 대기는 "배포" 아이콘에 빨간 점, 10/1). 현황 · 배포 상세의 환경 카드는 폰에서는 한 열, 넓은 화면에서는 나란히 보여요.

**디자인 (9/30, 박승준):**
- 재질 · 사이드바 · 움직임은 AfterPlan Mac 앱을 그대로 따라요: 사이드바는 HUD 재질(창 뒤 블렌딩), 본문은 창 뒤가 비치는 재질 한 장, 둘 사이에 선 없음. 선택 틴트는 스프링(0.32, 0.86)으로 미끄러지고 굵기는 즉시 바뀌어요. 사이드바 폭은 끌어서 190–420
- 버튼은 Craft 레퍼런스를 따라요: 화면마다 큰 제목 머리줄, 오른쪽에 동그란 글래스 버튼 · 캡슐 버튼 · 캡슐 세그먼트 (macOS 26 · iOS 26 이상은 Liquid Glass)
- **기능 UX는 웹과 맞춰요.** 같은 기능은 웹과 같은 흐름 · 용어 · 표기(리소스 `+/~/-` 등)를 써요. **기준은 웹 화면 코드(`web/feat-screens`, PR #18)**예요 (10/1 맞춤: 상태 라벨 `api/status.ts`, 단계 추정 `pages/flow.ts`, 시간 표기 `utils/format.ts`, 화면별 문구 · 버튼 · 확인 창). 디자인(색 · 모양 · 배치)은 앱 방식 그대로예요
- **보드 결정이 웹 코드보다 새로우면 보드를 따라요** (10/1): 빌드는 Jenkins(웹 목업은 아직 GitHub Actions), AI 호출 결과는 "호출 성공 · 호출 실패"(웹은 아직 "통과 · 실패"), 호출 기록은 `ai-usage?deployment_id=`(웹은 아직 A-04 `ai_usage.items`)

**메뉴 (웹 사이드바와 같은 구성):** 프로젝트 전환 · 새 배포 · PROJECT(개요 · 배포 · 환경 · 이력 · 스크립트) · ENVIRONMENTS(환경별 상태) · AI 사용량 · 설정 · 연결 상태 · 사용자. 좁은 화면은 같은 메뉴를 아이콘 탭 바로 (이름은 VoiceOver로 읽어요).
**배치 규칙:** 웹의 좌표는 참고만 하고, 앱 패턴(큰 제목 머리줄 · 카드 · 폭 따라 바뀌는 그리드 · 넓으면 표 좁으면 목록)으로 다시 놓아요. 버튼은 모두 글래스 양식(원 · 캡슐 · 캡슐 세그먼트)이고, 화면의 핵심 동작 하나만 강조 캡슐이에요.

| 웹 화면 | 앱 화면 | 들어가는 곳 | 필요한 API | 우선순위 |
|---|---|---|---|---|
| W-00 · W-00b 로그인 | `LoginView` | 앱 시작 (로그인 전) | R-02, R-09 (가칭) | M |
| W-01 개요 | `OverviewView` | 메뉴 개요 | A-01, A-02(+`image_digest` WR-09), A-03 | M |
| 메뉴 "배포" (웹 `CurrentDeployment`) | `DeploymentsView` → `RunView` | 메뉴 배포: **가장 최근 배포의 지금 단계**(W-05 ~ W-08)를 바로 열어요. 배포가 없으면 "아직 배포가 없어요". 지난 배포는 이력(W-09) | A-03 | M |
| W-02 애플리케이션 연결 → L-01 (입력은 GitHub 저장소 하나, W-02b 업로드는 범위 제외) | `ConnectAppView` | 프로젝트 전환 › 새 프로젝트 연결, 연결 해제 뒤 | WR-02, WR-03, A-06 | S |
| W-03 이미지 빌드 (Jenkins `daisy-ci`) | `BuildStage` | **사이드바 새 배포**(최근 빌드), L-01 뒤. 빌드가 끝나면 W-04로. Jenkins 화면은 외부 비공개라 로그 링크 없음 | A-06 | S |
| W-04 배포할 환경 선택 → L-02 | `TargetSelectView` | W-03 다음 (연결 안 되는 환경은 고를 수 없어요) | WR-04, WR-05 | M |
| W-05 인프라 코드 생성 · 검증 | `RunView` › `GenerateStage` | 배포 한 건 (apply 전) | A-04, WR-07 | M |
| W-05b ○○만 멈췄어요 | `RunView` › `StoppedStage` | 배포 한 건 (한 환경이 apply 전에 3회 실패, 나머지는 계속). "오류 로그 보기"는 웹과 같이 W-11 스크립트로 가요 | A-04, WR-05("○○만 다시 시도") | S |
| W-06 변경 사항 확인 후 승인 → L-03 | `PlanApprovalView` | 배포 한 건 (승인 대기), 개요 › 지금 할 일 | A-05 + WR-06, W-01 | M |
| W-07 배포 중 | `RunView` › `ApplyStage` | 배포 한 건 (배포 중) | A-04, A-07 | M |
| W-08 배포 결과 | `RunView` › `ResultStage` | 배포 한 건 (끝, `partially_succeeded`면 "일부 성공" 배지 · 성공한 환경끼리 동일성 비교: digest · 커밋 · 앱 버전 · 헬스) | A-04(환경별 `image_digest` · `health_summary`), A-07("원인 보기" 로그), WR-05(다시 시도) | M |
| W-09 배포 이력 | `HistoryView` | 메뉴 이력 (행 동작: 승인 대기 → 승인하기, 지난 성공 → 롤백, 나머지 → 결과) | A-03, WR-14 | M |
| W-10 환경 | `EnvironmentsView` | 메뉴 환경 | WR-04, A-10 · A-11 (가칭) | S |
| W-11 스크립트 | `ScriptsView` | 메뉴 스크립트 | WR-10 | S |
| W-12 AI 사용량 (배포 단위) | `AIUsageView` | 메뉴 AI 사용량 › 배포 고르기 | A-03, 합계 A-05 `ai_usage`, 호출 기록 `GET /projects/{id}/ai-usage?deployment_id=` (10/1 서버) | S |
| W-13 설정 | `SettingsView` (+ 앱 설정: 서버 주소 · 계정 · 버전) | 메뉴 설정 | A-12 (가칭), WR-03, WR-12, WR-13 | S |
| 푸시 알림 | — | 승인 필요 · 완료 · 실패 | P-01, P-02 | S |

M = 예선 데모 필수, S = 선택

---

## 3. 기술 구성

| 항목 | 선택 | 이유 |
|---|---|---|
| UI | **SwiftUI 멀티플랫폼 단일 타깃** (iPhone · iPad · Mac, 네이티브 macOS) | 코드 하나로 모든 화면. 레이아웃은 화면 폭 기준(탭 ↔ 사이드바, 적응형 그리드), `#if os(...)`는 플랫폼 전용 기능에만 |
| 최소 OS | iOS 18 · macOS 15 | `@Observable` · SwiftUI 최신 레이아웃 API. 2026년 9월 기준 심사위원 기기는 대부분 이보다 최신이에요 (아래 탭 바는 시스템 탭 대신 직접 그린 `SlimTabBar`) |
| 언어 · 도구 | Swift 6 (strict concurrency), Xcode 27 | |
| 외부 라이브러리 | **없음** (SPM 의존성 0개로 시작) | 웹 ADR-006과 같은 "최소 스택, 막힐 때만 추가" 원칙. 추가하면 이유를 ADR에 기록 |
| 네트워크 | `URLSession` + `async/await` + `Codable` | |
| 실시간 | `URLSession.bytes`로 **SSE를 직접 파싱** + 연결 실패 시 **5초 폴링** 폴백 | 웹과 같은 SSE 엔드포인트·이벤트를 그대로 써서 백엔드가 앱용으로 따로 만들 게 없음 (노션 결정 대기 "Swift 앱 실시간 수신"에 대한 제안) |
| 상태 관리 | 화면별 `@Observable` 스토어 | 앱 규모가 작아 별도 아키텍처 프레임워크는 쓰지 않음 |
| 인증 저장 | Keychain | 토큰을 UserDefaults에 두지 않음 |
| 푸시 | APNs (토큰 기반 `.p8` 키) | 백엔드가 발송 (§6-5) |
| 배포 | Xcode 아카이브 → App Store Connect → **TestFlight 외부 테스트 공개 링크** | |
| 목업 | **실서버가 기본.** 예외로 **예시 데이터 모드** 하나만 둬요 (9/30) | 로그인 화면 "예시 데이터로 둘러보기 (오프라인)" → 앱에 들어 있는 `SampleData/sample.json`(실제 sample-monolith · sample-msa 커밋 기반)으로 모든 화면을 봐요. 화면마다 "예시 데이터" 배지, 읽기 전용, 실데이터와 섞지 않아요. 만들기: `scripts/sample-data/generate.py` |

### 3-1. 폴더 구조

```
ios/
├─ AGENTS.md                AI 에이전트 규칙 (이 폴더 전용, 영어)
├─ SPEC.md                  이 문서
├─ Daisy.xcodeproj          앱 이름 Daisy, 번들 ID com.teamdaisy.daisy. 폴더 동기화 방식이라 파일을 추가해도 프로젝트 파일을 고칠 필요가 없어요
├─ Daisy/
│  ├─ App/                  진입점, 루트 화면 (폭 700 이상 사이드바 · 미만 아이콘 탭 바), 사이드바, 메뉴 · 경로(Workspace)
│  ├─ Features/             화면 단위 폴더. 각 폴더에 View + Store
│  │  ├─ Login/             W-00 로그인 · 데모 · 예시 데이터
│  │  ├─ Overview/          W-01 개요
│  │  ├─ Connect/           W-02 애플리케이션 연결 (L-01)
│  │  ├─ Deployments/       W-03 ~ W-08 배포 흐름 (RunView가 단계를 골라요), L-02 · L-03
│  │  ├─ Approvals/         W-06 변경 사항 확인 후 승인
│  │  ├─ History/           W-09 배포 이력 · 롤백
│  │  ├─ Environments/      W-10 환경
│  │  ├─ Scripts/           W-11 스크립트
│  │  ├─ AIUsage/           W-12 AI 사용량
│  │  └─ Settings/          W-13 설정 + 앱 설정
│  ├─ Core/
│  │  ├─ API/               APIClient, 엔드포인트(Endpoint · WebEndpoints), APIError, 예시 데이터(SampleData)
│  │  ├─ Models/            서버 응답 Codable 모델 (§6-7 · §6-8과 1:1)
│  │  └─ Auth/              토큰 저장 (Keychain)
│  │                        (Realtime/ SSE · Push/ APNs는 아직 없어요. 지금은 5초 폴링, D3에 추가)
│  ├─ DesignSystem/         재질, 글래스 버튼 · 세그먼트, 머리줄(PageScaffold · FlowPage), 카드, 상태 배지, 환경 아이콘, 시간 표기
│  └─ Resources/            에셋, SampleData/sample.json
├─ DaisyTests/              모델 디코딩 · 계약 · 문구 · 흐름 규칙 · 예시 데이터 테스트 (Swift Testing)
└─ scripts/                 testflight.sh · mac-dmg.sh · sample-data/generate.py
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

**앱이 하지 않는 것:** GitHub API 직접 호출, 클라우드 API 직접 호출, Terraform 실행, 대상 환경 등록·삭제. (배포 시작 · 롤백 · 연결 해제는 9/30부터 앱도 서버 API로 해요, §1-1)

---

## 5. 일정 (내 기준)

| 날짜 | 앱 | 백엔드에 필요한 시점 |
|---|---|---|
| D1 (9/29~30) | Xcode 프로젝트 생성, App Store Connect 앱 등록, 현황 · 배포 상세 화면 레이아웃, API 클라이언트 · 모델 | 이 문서 리뷰 → 이름 확정 ✅ (9/29) |
| D2 (10/1) | 로그인, 현황 · 배포 상세를 실서버에 연결 (5초 폴링), 승인 · 커밋 이력 화면 레이아웃. **TestFlight 외부 테스트 첫 빌드 심사 제출** (로그인 · 현황 · 배포 상세 기준) | 인증 R-01·R-02, 데모 계정 R-03, **A-01·A-02·A-04**, 개발 서버 R-08 (은현 님 약속) |
| D3 (10/2) | 배포 목록 · 승인 · 커밋 이력 연결, 폴링 → SSE 전환, 로컬 알림, 전체 흐름 리허설, 공개 링크 QR 준비. D3 기능을 넣은 빌드를 오전에 업로드 | A-03·A-05·A-06·A-07, SSE, 승인 W-01, (여유 있으면) 푸시 |
| 10/3 | 공개 링크 배포 | — |

- **TestFlight 외부 테스트는 첫 빌드에 Beta App Review가 필요해요.** 보통 하루 안팎이지만 보장되지 않아서 **10/1에 제출**하는 게 목표예요. 이후 빌드는 심사가 짧거나 생략되는 경우가 많지만 이것도 보장되지 않아요
- **업로드 준비 (9/30 완료):** App Store Connect 앱 **"Daisy Deploy"** 등록 (번들 ID `com.teamdaisy.daisy`, "Daisy"는 다른 계정이 써서 등록 이름만 달라요. 홈 화면 이름은 Daisy), 서명 팀 `X5F5WM2H6M`, 개인정보 매니페스트, **첫 빌드 0.1.0 (1) 업로드 완료**. 다음 빌드부터는 `ios/scripts/testflight.sh` 한 번이면 돼요
- **Mac 직접 다운로드 (9/30):** Developer ID 서명 · Apple 공증 · 스테이플한 DMG를 GitHub Releases에 올려요 (웹 W-14 "Mac 앱 받기"). 웹은 **고정 주소** https://github.com/Softbank-Hackathon-2026-Team-Daisy/daisy/releases/download/mac-latest/Daisy.dmg 를 써요 (새 빌드 때 파일만 바꿔요). 지금 0.1.0 (2610011659, 예시 데이터 포함, `mac-v0.1.0-2610011659`), macOS 15 이상. 앱이 바뀔 때마다 새 릴리스 + 고정 주소 파일을 바꿔요 (10/1). 만들기는 `scripts/mac-dmg.sh`
- **TestFlight 그룹 (9/30):** 내부 `Team Daisy`(자동 배포, 심사 없음) · 외부 `Public Link` → **https://testflight.apple.com/join/wF5sjQPG** (Beta App Review 통과 뒤 열려요). macOS 플랫폼 추가, macOS 빌드 0.1.0 (2609301801) 업로드 · 처리 완료
- **남은 것:** 외부 테스트 공개 링크는 Beta App Review용 서버 HTTPS 주소 · 데모 계정(R-03)이 필요해요. 앱 아이콘 원본이 200×200이라 1024에서 조금 흐려서 **1024 이상 원본(또는 SVG)으로 바꿔야 해요**
- 앱은 로그인이 필요해서 심사 때 **Apple 심사자용 계정**을 적어 내야 해요. 그래서 데모 계정(§6-1 `R-03`)과 HTTPS 서버(`R-04`)가 **D2까지 꼭 필요해요.** 데모 계정은 D2 약속을 받았고, HTTPS는 9/29 회의에서 도메인을 사서 적용하기로 했어요 (서버 담당, 9/30 오후 전)
- 승인 · 커밋 이력은 서버 API가 D3에 나와서, 첫 심사 빌드에는 레이아웃만 들어가요. 심사를 통과한 뒤 올리는 빌드는 다시 심사받지 않는 경우가 많지만 보장되지 않아서, D3 빌드를 오전에 올려요
- 실서버 연결은 **백엔드 API 일정에 직접 묶여요.** 그동안은 예시 데이터 모드(9/30)로 모든 화면을 확인 · 시연해요

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
| A-06 🆕 | `GET /projects/{id}/builds?cursor=` | **W-03 이미지 빌드** | `Build[]` (§6-7) | M | Jenkins `daisy-ci`가 보낸 빌드 결과(9/30 회의: GitHub Actions 대신 Jenkins)를 저장해 두고 돌려주면 돼요. 커밋별 **배포된 환경 목록**까지 |
| A-07 🆕 | `GET /deployments/{id}/logs?target_id=&tail=200` | W-07 로그 (200줄), W-08 "원인 보기" 로그 화면 (500줄) | 최근 로그 N줄 | S | SSE가 끊겼다 들어왔을 때 최근 로그 채우기용 |
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
- `confirm_text`: 웹 · 앱 모두 **프로젝트 이름**(예: `sample-monolith`)을 입력받아 보내요 (10/1, 웹 W-06과 같게). 서버가 같은 값으로 검증하는지는 §6-9 확인 대기 `(가칭)`
- viewer 역할이면 **403** (R-03)
- **plan을 다시 뜨는 경우 (9/29, 하은현):** 승인 대기가 길어져 plan이 낡으면(stale) 서버가 plan을 다시 뜨고 이전 승인은 무효가 돼요. 이건 AI 수정이 아니라서 **`attempt`는 그대로**이고, `approval.required`가 다시 와요. 앱은 같은 "시도 n/3"으로 승인 카드를 다시 띄우고, "plan이 갱신됐어요"처럼 이유를 보여줘요
- **승인 단위**: 웹 · 앱 모두 **승인 대기인 환경 전부를 한 번에** 승인해요. 3회 실패한 환경은 "이번 승인에서 빠져요"로 보여줘요 (웹 W-06과 같게). 서버 동작 확인은 §6-9

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
- 빌드(커밋)별 **메시지 · 작성자 · 시각 · Jenkins 결과 · 실행 링크 · 이미지 태그 · 배포된 환경**

### 6-7. 데이터 모델

앱의 `Core/Models`와 1:1로 맞출 모양이에요. `Plan`은 서버의 `PlanSummary` 기준이에요. 나머지 필드 이름은 서버 OpenAPI가 나오면 맞추고, 그때까지는 `(가칭)`이에요.

```jsonc
// Project
{ "id": "prj_1", "name": "sample-monolith", "repository": "https://github.com/Softbank-Hackathon-2026-Team-Daisy/sample-monolith", "branch": "main" }
// repository는 W-02에서 입력한 전체 URL 그대로 (웹과 같아요)

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
  "checked_at": "2026-10-03T10:13:00Z",
  "image_digest": "sha256:…" | null,        // WR-09 동일성 검증 (W-01)
  "health_summary": "200 OK · 120ms" | null  // 없으면 "정상" · "실패"
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
      "error_summary": null,
      "image_digest": "sha256:…" | null,     // W-08 동일성 검증 (apply가 끝난 환경) — 웹 A-04와 같아요
      "health_summary": "200 OK · 120ms" | null   // 헬스체크 1회 측정 (10/1 인프라)
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
      "risks": [ { "level": "high", "rule": "sg-open-world", "resource": "aws_security_group.web", "message": "보안 그룹이 0.0.0.0/0에 열려 있어요" } ],
      "summary": "이미지 태그만 교체" | null,  // W-06 환경별 요약 끝말 (웹과 같아요). 없으면 "위험 설정 n건"
      "plan_text": "…" | null                 // W-06 plan 원문. 없으면 리소스 목록만
    }
  ],
  "ai_usage": { "tokens": 18234, "cost_krw": 312, "exchange_rate": 1400, "estimated": true, "calls": 3 }
  // 배포 한 건의 합계 (10/1 서버: 승인 화면 합계는 A-05에). 서버는 USD로 합산한 뒤 고정 환율로 원화 환산해요
}

// AI 호출 한 번 — GET /projects/{id}/ai-usage?deployment_id= (10/1 서버 결정, 목록 봉투는 `{ items, next_cursor }` 가정)
{
  "at": "…", "deployment_id": "dep_42", "target_id": "tgt_aws",
  "step": "generate" | "fix", "attempt": 2,
  "tokens": 1860 | null, "cost_krw": 48 | null,  // 확인 못 한 값은 0이 아니라 null → 화면 "—"
  "status": "succeeded" | "failed",              // LLM 호출 성공 · 실패 (Terraform 검증과 별개) → "호출 성공 · 호출 실패"
  "note": "보안 그룹 0.0.0.0/0 수정" | null        // 필수 아님 (웹 목업 이름은 `title`, 앱은 둘 다 받아요)
}

// Build — A-06, 커밋·파이프라인 화면
{
  "commit": "2311c0b…",
  "message": "feat(ci): Daisy 앱 연결 요구사항 추가",
  "author": "Seungjun1127",
  "committed_at": "…",
  "pipeline": { "status": "running" | "success" | "failed", "run_url": "https://<jenkins>/job/daisy-ci/42/" | null },  // Jenkins 빌드 링크 (§6-9)
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
| WR-05 | `POST /projects/{id}/deployments` `{ commit, target_ids[] }` + `Idempotency-Key` | W-04 시작, **W-05b "○○만 다시 시도"(실패한 환경 전부) · W-08 "다시 시도"도 같은 커밋 · 그 환경만으로 새 배포** | 이 경로로 확정 · D2. 재시도 = 새 배포, 시도는 1/3부터 ✅ (10/1 #13). 요청 필드는 OpenAPI 대기 |
| WR-06 | `GET /deployments/{id}/plan?detail=resources` | W-06 리소스 행 (`action`에 `replace` 포함) | 좋아요 · D3 |
| WR-07 | `GET /deployments/{id}/targets/{target_id}/script` → `files[{ path, content }]` | W-05 생성된 스크립트 | 18시 백엔드 회의에서 확인 |
| WR-08 | `POST /deployments/{id}/cancel` | (앱은 아직 버튼 없음) | 좋아요 · D3. **apply 도중에는 중단하지 않고 서버가 결과를 기다려요** (10/1 17:23, #17) — 앱도 apply 시작 뒤에는 취소를 보여주지 않아요 |
| WR-09 | A-02에 `image_digest` (+ A-04 환경별 `image_digest`) | W-01 동일성(A-02, 배포된 첫 환경 기준) · W-08 동일성(A-04, 성공한 첫 환경 기준) — 웹과 같은 규칙 | A-02 넣을게요 · D2. A-04 환경별 값은 §6-9 확인 대기 |
| WR-10 | `GET /projects/{id}/scripts` | W-11 | 승환 님 영역, D3~ |
| WR-11 | W-12 AI 사용량: **합계는 A-05 `ai_usage`, 호출별 기록은 `GET /projects/{id}/ai-usage?deployment_id=`** | W-12 (배포 단위) | ✅ 10/1 00:29 서버 결정 (#13). 앱 반영 완료. 목록 봉투 · 필드 이름은 OpenAPI 대기 (§6-9). plan이 아직 없으면 배포에 온 합계, 기록이 없으면 합계 · 재사용 줄만 보여줘요 |
| WR-12 | `PUT /projects/{id}/secrets/{name}` | W-13 비밀값 추가 (지금은 비활성) | 전달 방식 팀 결정 대기 |
| WR-13 | `DELETE /projects/{id}` | W-13 연결 해제 (확인 입력은 화면에서) | 좋아요 · S |
| WR-14 | `POST /deployments/{id}/rollback` `{ target_ids[], reason }` → `Deployment(kind: "rollback")` | W-09 롤백 → 새 배포로 이동, **plan 승인을 거쳐요** | 넣을게요 (은현 님) |

**앱이 더 부탁하는 것 (가칭) 🆕** — 웹 W-10 · W-13 · W-00에도 같은 버튼이 있어요. 받으실지는 서버가 정해 주세요 (이슈로 전달)

| ID | 메서드 · 경로 (가칭) | 앱 화면 | 요약 |
|---|---|---|---|
| R-09 | `POST /auth/demo` → `AuthToken(role: "viewer")` | W-00 "데모 계정으로 둘러보기 (읽기 전용)" | 심사위원이 비밀번호 없이 들어오는 버튼. **인증 범위는 9/30 회의 안건**이라 결정 뒤 맞춰요. `/auth/token` + 공개 데모 계정으로 대신해도 돼요 |
| A-10 | `POST /targets/{id}/test` → `{ connected, message }` | W-10 "연결 테스트" | WR-04 `connection`을 지금 다시 확인 |
| A-11 | `GET /targets/{id}/resources` → `{ items: [{ address, type }], next_cursor }` (목록 봉투, §6-9 S-1) | W-10 "리소스 보기" | 이 환경 state에 있는 리소스 |
| A-12 | `GET /projects/{id}` → `id, name, repository, branch, build?, registry?, webhook_last_at?` | W-13 저장소 카드 | 노션 계약 v0.2 §3-2 제안과 같아요 |

**기존 모델에 더한 필드 (가칭) 🆕** — 없으면 화면이 "—"나 기본 문구로 보여줘요. 필수는 아니에요.

- `Deployment`: `version`("v7"), `commit_message`
- AI 호출 기록 (W-12): §6-7 "AI 호출 한 번" 모양. 재사용 환경은 기록이 없어서 앱이 `reused_script`로 "— 검증된 스크립트 재사용" 줄을 만들어요
- `Deployment.targets[]`: `title`("home-lab · Docker"), `steps[]`(`{ name, state, duration_ms, started_at }`, W-05 검증 단계 · W-07 레인. **없으면 웹처럼 추정**: W-05 "Terraform 생성 (AI) · terraform validate · terraform plan · 위험 설정 검사", W-07 "이미지 pull · terraform apply · state 저장 · 헬스체크"), `health_summary`("200 OK · 120ms", 1회 측정), `image_digest`
- `Plan.targets[]`: `reused_script`, `summary`, `plan_text`
- `Build`: `branch`, `digest`, `steps[]` (W-03 Jenkins 단계)
- `Project`: `branch`
- WR-04 `Target`: W-10 줄 `title, runtime, location, location_label("위치" · "리전"), access_method, exposure, state_backend, current_commit`. `reuse.reason`은 카드 설명 그대로 써요 ("home-lab Proxmox VM · 사설망 · 검증된 스크립트 있음 → 태그만 교체")
- A-07 로그 줄: 앱 초안 `ts · text`, 웹 목업 `seq · at · message` — 둘 다 받아요 (§6-9)
- WR-03 `Manifest.errors`: 웹 목업은 문자열 배열, 앱 초안은 `{ path, message }` — 둘 다 받아요 (§6-9)
- WR-10 `Script`: W-11 정보 카드 `note, base_commit, input, ai_tokens, storage, created_at`
- WR-03 `Manifest`: `raw`(원문), `ref`("deploy.yaml · main@a1b2c3d")

**9/30 저녁에 뺀 것:** A-09 동일성 검증 API(→ WR-09), B-01 저장소 미리 확인(→ WR-02 응답 + WR-03), B-03 · B-04 업로드(범위 밖), B-09 · B-11 재시도 API(→ WR-05 새 배포), B-10 "○○ 빼고 계속"(Q7: 나머지 환경은 자동으로 계속), 상태 `building` · `selecting_targets` · `stopped`(W-03 · W-04는 배포가 생기기 전 화면), 인프라 월 비용(서버 보류, 오면 보여줘요)

### 6-9. 미정: 서버 · 인프라 결정 대기 (10/1)

보드(`ios/BOARD.md`)에 결정이 없어서 **앱이 가정으로 두고 있는 것**이에요. 결정이 나면 앱은 모델 · 요청 한 곳만 고치면 돼요. 각 담당 브랜치 · PR에 질문을 남겼어요 (10/1).

| # | 담당 | 미정 항목 | 앱이 지금 가정하는 것 | 결정 안 나면 앱은 |
|---|---|---|---|---|
| S-1 | 서버 (하은현) | 목록 응답 봉투: 모든 목록(A-02 · WR-04 · 새 `ai-usage`)이 `{ items, next_cursor }`인지 | 모두 봉투 | 배열이 오면 디코딩 실패 → 한 줄 수정 |
| S-2 | 서버 (김승환) | `ai-usage` 호출 한 줄 필드: 작업 설명 이름(`note` / `title`), `calls`를 A-05 합계에 넣는지 | `note` 또는 `title`, `calls` 있으면 씀 | 설명이 없으면 "Terraform 생성 (deploy.yaml)" · "Terraform 수정"으로 대신, 모르는 `status`는 "—" |
| S-3 | 서버 (하은현 · 김승환) | A-04 환경별 `image_digest` · `health_summary` · `steps[]` 제공 여부 (10/1 "제공 · 후순위 · 미제공으로 안내" 약속) | 오면 쓰고, 없으면 "—" · 웹처럼 단계 추정 | W-08 동일성 digest 줄이 "—" |
| S-4 | 서버 (하은현) | 승인 `confirm_text` 검증 값 = 프로젝트 이름인지, 승인 대기 환경만 적용되는지 | 프로젝트 이름, 승인 대기 환경 전부 한 번에 | 서버가 다른 값을 요구하면 입력 안내만 바꿔요 |
| S-5 | 서버 (하은현) | `POST /projects` 응답: `Project`만 / `{ project, manifest }` (웹 목업) | `Project` → `GET manifest` 따로 | 둘 다 받게 한 줄 수정 |
| S-6 | 서버 (하은현) | 로그 줄 필드(`ts · text` / `seq · at · message`), `Manifest.errors` 모양 | 둘 다 받아요 | 영향 없음 |
| S-7 | 서버 (하은현) | 로그인 없이 읽기 전용 둘러보기(9/30 회의) 방식: `POST /auth/demo` 같은 viewer 토큰 발급인지, 심사위원 테스트 계정 전달 방식 | R-09 `POST /auth/demo` (가칭) | 버튼만 두고 오류 표시. **TestFlight 외부 심사에 계정이 필요**해요 |
| S-8 | 서버 (하은현) | 앱 추가 요청 A-10 연결 테스트 · A-11 리소스 보기 · A-12 프로젝트 상세를 받을지 | 경로 (가칭) | 버튼은 켜 두고(웹도 같은 버튼이 있어요), 서버가 없다고 하면 "연결 테스트를 하지 못했어요" 같은 안내 |
| S-9 | 서버 (하은현) | 개발 서버 주소 · 열리는 시각 (R-08) | — | 예시 데이터 모드로만 확인 |
| I-1 | 인프라 (황지환) | **API 서버의 HTTPS 주소** (`daisydeploy.dev` 하위 이름 · 공인 인증서). iOS는 HTTPS가 아니면 연결을 막아요(ATS) | — | TestFlight 외부 링크 심사 제출 불가 |
| I-2 | 인프라 (황지환 · 임채준) | Terraform state 저장소 (W-10 "state" 줄) | ✅ 일부 답 (10/1 임채준, #17): 환경이 제공하는 저장소 + 잠금 — AWS "S3 (잠금)", GCP "GCS (잠금)". **온프레미스는 황지환 님과 정하는 중**, key는 `{project_id}/{target_id}` 방향(은현 님과 확정) | 서버가 준 이름, 없으면 `[미정]` |
| I-3 | 인프라 · CI (임채준) | 이미지 레지스트리 (W-13 "레지스트리" 줄) | 임채준 답(10/1, #17): **Docker Hub**, 이미지 `docker.io/<계정>/<앱>:<커밋 해시>`, 계정 이름은 확정 뒤 알려 주기로. 보드에는 아직 팀 결정으로 안 올라가서 앱은 `[미정]` 표시를 유지해요 | `[미정]` 그대로 |
| I-4 | 인프라 · CI (임채준) | Jenkins 빌드 링크 · 단계 이름 | ✅ 10/1 임채준 답: Jenkins 화면은 외부 비공개 → **앱 "Jenkins 로그 열기" 버튼 숨김(반영)**. 서버가 Jenkins API(빌드 상태 · 단계 · 로그)로 받아서 넘겨요. 단계: CI `Checkout → Test → Build & Push → Trigger CD`, CD `Prepare → Infra code → Plan → Risk check → Approve → Apply → Health check` | — |
| I-5 | 인프라 (황지환 · 임채준) | 환경별 공개 URL 형식 (W-08 QR · "열기"), 헬스 결과 | AWS는 ✅ 10/1 임채준 답: URL · 상태 코드 · **1회 측정 응답 시간(ms)** 제공, p95는 어려움 → "200 OK · 120ms" 형식(반영). 온프레미스 URL 모양은 황지환 님 답 대기 | "—" |
| I-6 | 팀 | 헬스체크 실패 시 자동 롤백 | 10/1 임채준 답: AWS는 새 컨테이너가 헬스체크를 통과해야 트래픽을 옮겨요. 실패하면 **이전 컨테이너가 계속 서비스하고 CD 결과는 실패**. "실패 + 이전 버전 유지" 구분은 CD → 서버 결과 전달 방식이 정해지면 추가 | 실패로 표시 (롤백은 `kind: "rollback"` 새 배포만) |

## 7. CI 요구사항 (가칭) — 인프라팀 (Jenkins)

> **9/30 21시 회의: CI/CD 도구는 GitHub Actions 대신 Jenkins**예요. **10/1 10:42: CI/CD 일은 전부 인프라팀 담당**이에요 (김승환 님 스레드). 그래서 이 절의 받는 사람은 김도영 님이 아니라 **인프라팀(임채준 · 황지환)**이에요.
> 10/1 임채준 답(#17): 서버가 **Jenkins API로 빌드 상태 · 단계 · 로그를 직접 받아요** (`wfapi/describe`, `logText/progressiveText`, `api/json`). 그래서 아래 C-02 · C-03(실패 · 시작 이벤트)은 서버가 Jenkins 상태를 읽는 것으로 대신할 수 있어요. C-01(커밋 메시지 · 작성자 · 시각)만 서버가 어디서 받을지 정해지면 돼요.

커밋 · 파이프라인 화면(A-06)을 채우려면 빌드가 보내는 이벤트에 정보가 조금 더 필요해요. 이 payload는 서버 웹훅으로 들어가서, **은현 님이 정리해 전달**하기로 했어요 (9/29).

| ID | 요구사항 | 우선 | 비고 |
|---|---|---|---|
| C-01 🆕 | payload에 `commit_message`, `author`, `committed_at` 추가 | M | Jenkins에서는 `git log -1` 값이나 GitHub 웹훅 본문에서 가져올 수 있어요. 없으면 백엔드가 GitHub API로 따로 가져와야 해요 |
| C-02 🆕 | **실패해도 이벤트 전송** (`status: "failed"`) | S | Jenkins `post { always { … } }`에서 결과값 전달 |
| C-03 🆕 | 파이프라인 시작 시 `status: "running"` 이벤트 | S | 커밋 화면에서 "빌드 중" 표시 |

---

## 8. 결정이 필요한 것 ❓

- [x] ~~ADR-007 범위 수정~~ → 앱도 웹과 같은 전체 흐름 (10/1 팀장 결정, #33)
- [x] ~~Bearer 토큰 병행~~ → Bearer 하나로 통일 (9/29, 은현 님)
- [x] ~~개발 서버 · 데모 계정 준비~~ → D2 은현 님 (9/29)
- [x] ~~HTTPS 공개 주소 (R-04)~~ → 도메인 구매 + HTTPS (9/29 회의, 서버 담당)
- [x] ~~승인 단위~~ → 웹 W-06과 같이 승인 대기 환경 전부 한 번에 (10/1 웹 코드). 서버 동작 확인은 §6-9 S-4
- [x] ~~`confirm_text` 값~~ → 프로젝트 이름 (10/1 웹 코드와 같게). 서버 검증 값 확인은 §6-9 S-4
- [x] ~~앱 범위를 웹 전체로 넓힐지~~ → 넓혀요 (10/1 ADR-007 확정, `web/SPEC.md` §1-1도 같은 내용으로 고쳐졌어요)
- [ ] **§6-8 앱 추가 요청 R-09 · A-10 ~ A-12 · 필드 추가**를 서버가 받을지 — 하은현 · 김승환 (이슈로 전달)
- [ ] **데모 계정 진입 방식** (R-09): 9/30 회의에서 "로그인 안 하면 읽기 전용 둘러보기 + 심사위원 테스트 계정 1개"로 정해졌어요. API 방식은 §6-9 S-7 — 서버
- [ ] **Q4 빌드가 끝나면 W-04로 바로 갈지** — 앱은 지금 바로 넘어가요. 웹 W-03 코드(`BuildPage.tsx`)가 PR #18에 아직 없어서 확인 대기 — 웹
- [ ] **헬스체크 실패 시 자동 롤백** (은현 님 제안): 넣으면 이력에 롤백 배포가 승인 없이 생겨요. 앱은 `kind: "rollback"`으로 표시만 해요 — 팀
- [x] ~~배포 상태 · 단계 값~~ → 9/30 서버 확정 (§6-7): 배포 전체 `queued · running · awaiting_approval · succeeded · partially_succeeded · failed · cancelled`, 환경별 `waiting · generating · validating · awaiting_approval · applying · verifying · succeeded · failed · cancelled`. 롤백은 별도 배포
- [x] ~~Q7 한 환경 3회 실패 시~~ → 환경별, 나머지는 계속 (9/29 서버). W-05b는 "○○만 멈췄어요" + "○○만 다시 시도" (9/30 도영 님 와이어프레임 수정)
- [x] ~~"○○만 다시 시도" 방식~~ → 실패한 대상만 고른 새 배포, 시도는 1/3부터 (10/1 #13 서버). 버튼 하나로 실패한 환경 전부 (웹과 같게)
- [x] ~~W-12 범위~~ → 배포 단위 (9/30 도영 님)
- [x] ~~W-12 응답 위치~~ → 합계 A-05, 호출 기록 `ai-usage?deployment_id=` (10/1 #13 서버)
- [x] ~~AI 호출 기록 `status`의 뜻~~ → LLM 호출 성공 · 실패, 화면 "호출 성공 · 호출 실패" (10/1 #13 서버). 웹은 아직 "통과 · 실패"라 웹 쪽 맞춤이 남아요
- [x] ~~CI 도구~~ → Jenkins (9/30 회의). W-03 · 예시 데이터를 Jenkins로 바꿈 (10/1)
- [x] ~~LLM~~ → Claude (9/30 김승환). W-12 비용 설명에 표시
- [x] ~~롤백 표시~~ → 새 배포 한 건, 목록 · 알림에서 일반 배포처럼 (9/30 도영 님)
- [x] ~~업로드 입력(W-02b)~~ → 서버 작업 없음, 앱은 설계만 표시 (9/30 은현 님 답변. 웹 화면 처리는 도영 님 결정)
- [x] ~~푸시를 예선 범위에 넣을지~~ → D3까지 로컬 알림, APNs는 여유 있으면 (9/29)
- [x] ~~경로 · 이벤트 이름 확정~~ → 9/29 확정. 모델 필드는 서버 OpenAPI가 나오면 맞춰요

---

## 9. 변경 기록

| 날짜 | 변경 | 작성 |
|---|---|---|
| 10/1 | **ADR-007 확정 반영** (앱도 웹과 같은 전체 흐름, #33): §1-1 · §1-2 · §8. 서버 역할 `owner` · `viewer`, `ai_usage.attempt` = 생성 · 수정 회차(1–3)는 앱의 기존 처리와 같아요 (PR #32) | 박승준 |
| 10/1 | 스펙 · 구현 대조로 오래된 문장 정리 (§1 화면 이름, §3 폴더 구조 · 최소 OS 이유, §4 앱이 하는 일, §5 DMG 버전, A-07 줄 수, A-11 봉투, Project.repository 전체 URL, TargetStatus `image_digest` · `health_summary`, 헬스 "200 OK · 120ms", W-05b 오류 로그 → 스크립트, WR-08 apply 도중 중단 없음(17:23 결정)). 코드: 이력 "롤백 · 롤백됨" 중복, 모르는 AI 호출 상태 "—", iPhone 배포 화면 "새 배포" 버튼 | 박승준 |
| 10/1 | iPhone 아래 탭을 얇은 글래스 캡슐 아이콘 바로 (글씨 없음, "더 보기" 없음, 선택한 탭은 채운 아이콘, 환경 아이콘 `square.stack.3d.up`, AI 사용량 `chart.bar`). 화면 머리줄(루트 · 흐름 화면)을 뒤가 비치는 반투명 재질로, 모든 화면 끝까지 스크롤(탭 바 위 여백), W-05 아래 빈 공간 수정 | 박승준 |
| 10/1 | 인프라 답(#17 임채준) 반영: W-03 "Jenkins 로그 열기" 숨김(외부 비공개), CI 단계 이름, 헬스 "200 OK · 120ms"(1회 측정), state "S3 (잠금)" · "GCS (잠금)", ECS 실패 시 이전 컨테이너 유지 → 실패로 표시. §7 담당을 인프라팀으로(10:42 결정). 웹 결정(12:11) 반영: 끝난 배포 · 빌드는 폴링 멈춤, 동일성 헬스 줄은 `health_summary` 그대로 | 박승준 |
| 10/1 | **보드 · 웹 최신화 맞춤**: Jenkins(W-03 · 연결 안내 · 예시 데이터), W-12 합계 A-05 + `ai-usage?deployment_id=` · "호출 성공 · 호출 실패" · 확인 못 한 토큰 "—", 상태 라벨 "취소됨 · 확인 중 · 롤백됨 · 확인 전". 웹 PR #18 화면 흐름 · 문구: 메뉴 "배포"=최근 배포 지금 단계, "새 배포"=W-03, W-02 업로드 제거 · URL 형식 검사, W-04 연결 안 되는 환경 선택 불가, W-05 · W-05b 한 줄 · 단계 추정(`flow.ts`) · "○○만 다시 시도"(실패 환경 전부) · "변경 사항 확인하기", W-06 승인 대기 환경만 · 프로젝트 이름 확인 · 승인 바 문구 · 거절 뒤 개요, W-07 단계 · 배지, W-08 동일성(A-04 기준, 앱 버전 줄), W-09 행 동작 · 롤백 창(환경 고르기 · 프로젝트 이름), W-10 · W-11 · W-13 문구 · 연결 해제 창, 24시간제 · 상대 시각. §6-9 미정 표 추가. 테스트 55 → 64개 | 박승준 |
| 9/29 | 초안 작성 | 박승준 |
| 9/29 | 앱 목업 모드 제거 (항상 실서버 연결), 개발 서버 요구(R-08) 추가 | 박승준 |
| 9/29 | 에이전트 규칙 파일을 `CLAUDE.md` → `AGENTS.md`로 변경 | 박승준 |
| 9/29 | 서버 답변 반영: 경로 · 이벤트 이름 확정, Bearer만, `DELETE /devices` + 본문, `attempt` 의미, Plan 모양(`level`·`resource`, `ai_usage`), 제공 일정 D2/D3, 폴링 · 로컬 알림 폴백 | 박승준 |
| 9/30 | 예시 데이터 모드(오프라인 번들, 배지, 읽기 전용) 추가 — 9/29 "목업 없음" 결정을 담당자가 바꿈. 생성 스크립트 · 테스트 6개 | 박승준 |
| 9/30 | Mac DMG 공증 · GitHub Releases 첫 릴리스, `scripts/mac-dmg.sh` | 박승준 |
| 9/30 | TestFlight 첫 업로드 ("Daisy Deploy" 0.1.0 (1)), 업로드 스크립트 `scripts/testflight.sh` | 박승준 |
| 9/30 | 도영 님 와이어프레임 수정 반영: W-05b "○○만 멈췄어요 / ○○만 다시 시도", W-08 "일부 성공" 배지와 설명, W-09 롤백을 일반 배포처럼, W-12 배포 단위(A-04 `ai_usage`, WR-11 안 씀). 모듈 테스트 추가 (`RunLogicTests` · `AIUsageSummaryTests` · `EndpointContractTests` · `ContractDecodingTests`) | 박승준 |
| 9/30 | 팀 방향에 맞춤: 서버 확정 상태 두 층, 웹 `WR-xx` 경로 · 모양 그대로 사용(배포 시작 `POST /projects/{id}/deployments`, 롤백은 새 배포 + 승인, 동일성은 `image_digest`), Q7 반영("빼고 계속" 제거), 업로드 설계만, W-03 · W-04를 배포 전 화면으로. §6-8을 WR-xx + 앱 추가 요청(R-09, A-10 ~ A-12)으로 다시 씀 | 박승준 |
| 9/30 | 와이어프레임 v1.0 화면 · 문구 · 버튼을 앱에 모두 옮김 (W-00 ~ W-13, L-01 ~ L-03), 메뉴를 웹 사이드바 구성으로, 새 요청 §6-8 (가칭) | 박승준 |
| 9/30 | 웹(Figma 와이어프레임 v1.0) 문구로 통일: 메뉴 개요 · 배포 · 승인 · 이력 · 설정, 상태 이름, `리소스 +6 ~0 −0`, 로그인 · 오류 문구. 색 · 모양은 앱 방식 유지, 아이콘은 비슷한 SF Symbols | 박승준 |
| 9/30 | 앱 아이콘 적용 (iOS 1024 꽉 찬 정사각형, macOS 둥근 사각형 격자 16–1024), 사이드바 머리에 로고 | 박승준 |
| 9/30 | 디자인 적용: AfterPlan 재질 · 사이드바 · 움직임, Craft 버튼(글래스 원 · 캡슐 · 세그먼트), 큰 제목 머리줄, 웹과 기능 UX 맞추기 | 박승준 |
| 9/30 | 반응형으로 변경: 최소 iOS 18 · macOS 15, 탭 ↔ 사이드바 자동 전환, 현황 · 배포 상세 적응형 카드 그리드 | 박승준 |
| 9/30 | 앱 뼈대 구현 후 최신화: A-02 목록 봉투 가정, `confirm_text` 값 질문, TestFlight 업로드 준비물 | 박승준 |
| 9/30 | 리뷰 반영: "총 시도 횟수" 문구(승환 님), plan 재생성 시 재승인 동작(은현 님), AI 비용 추정 · 환율 표시(`server/AGENTS.md`), R-04는 도메인 + HTTPS로 확정(9/29 회의) | 박승준 |
