# CLAUDE.md — ios/ (Swift 앱 · iOS · macOS)

> 담당: 박승준 · 상태: **초안 (9/29)**
> 루트 `CLAUDE.md`의 공통 규칙을 먼저 따르고, 이 파일에는 **이 폴더에만 해당하는 규칙**만 적어요.
> 화면 · 구조 · 백엔드 요구사항 전체는 [`SPEC.md`](./SPEC.md)에 있어요. 작업 전에 **SPEC.md를 먼저 읽어요.**

## 이 폴더가 하는 일
- Daisy 배포 현황을 iOS · macOS에서 보는 네이티브 앱: **보기 + 승인 + 알림**
- 화면: 현황(환경별 현재 버전), 배포 목록 · 상세, 승인, 커밋 · 파이프라인, 설정 (SPEC §2)
- 하지 않는 것: 배포 시작, 대상 환경 등록 · 삭제, GitHub · 클라우드 API 직접 호출, Terraform 실행 (SPEC §4)
- ADR-007 범위 수정 제안 중 (SPEC §1-2). 확정 전까지 M 화면만 만들어요

## 기술 스택
- SwiftUI 멀티플랫폼 단일 타깃, iOS 17+ · macOS 14+ (`@Observable` 사용)
- Swift 6 strict concurrency, Xcode 27
- **SPM 외부 의존성 0개**로 시작. 막힐 때만 추가하고 이유를 노션 ADR에 기록 (웹 ADR-006과 같은 원칙)
- 네트워크 `URLSession` + `async/await` + `Codable`, 실시간은 `URLSession.bytes`로 SSE 직접 파싱 + 5초 폴링 폴백
- 토큰은 Keychain, 푸시는 APNs

## 폴더 구조
```
ios/
├─ Daisy.xcodeproj
├─ Daisy/
│  ├─ App/            진입점, 루트 화면 (iOS TabView / macOS NavigationSplitView), 의존성 조립
│  ├─ Features/       화면 단위: Overview, Deployments, Approvals, History, Settings (각각 View + Store)
│  ├─ Core/           API, Models, Realtime, Auth, Push
│  ├─ DesignSystem/   공용 뷰: 상태 배지, 환경 아이콘, 커밋 해시 라벨, MOCK 배지
│  ├─ Mock/           MockAPIClient, Fixtures/*.json, Events/*.jsonl
│  └─ Resources/
├─ DaisyTests/
└─ DaisyWidgets/      (선택) 위젯 · Live Activity
```

## 컨벤션
- 이름 규칙: 타입 `UpperCamelCase`, 나머지 `lowerCamelCase`. 화면은 `{Feature}View`, 상태는 `{Feature}Store`
- 파일 배치: 한 화면에서만 쓰는 뷰는 그 `Features/{Feature}/` 안에. 두 화면 이상에서 쓰면 `DesignSystem/`
- 서버 모델: `Core/Models`에만 두고 SPEC §6-7과 1:1. JSON은 `snake_case` → `convertFromSnakeCase`로 디코딩
- enum: 서버 문자열 enum에는 항상 `unknown` 케이스를 둬서 새 값이 와도 죽지 않게 해요
- 에러 처리: 서버 에러 봉투 `{ error: { code, message, retryable } }`를 `APIError`로 변환. `STATE_CONFLICT`(409)는 최신 상태 재조회, `UNAUTHENTICATED`(401)는 로그인 화면
- 플랫폼 분기: `#if os(iOS)` / `#if os(macOS)`는 `App/`과 `DesignSystem/`에서만. 화면 로직에는 넣지 않아요
- 문자열: 화면 문구는 한국어, 해요체
- 테스트: 모델 디코딩(픽스처 JSON), SSE 파서, 스토어 상태 전이

## 다른 파트와의 약속
- 웹과 **같은 API 계약** 사용. 앱 때문에 필요한 API · 필드는 SPEC §6 · §7에 `(가칭)`으로 적어 두고 회의에서 확정
- 실시간: 웹과 같은 SSE 엔드포인트 · 이벤트. SSE가 늦어지면 조회 API 폴링으로 대체 (SPEC §6-3)
- 인증: Bearer 토큰 병행 요청 중 (SPEC R-01)
- APNs 키(`.p8`)는 박승준이 발급해 비밀값으로 전달 (SPEC P-03)

## 실행 방법
```bash
open ios/Daisy.xcodeproj
```
- 백엔드 없이 개발할 때는 설정 → **목업 모드**를 켜요 (화면에 MOCK 배지가 떠요)
- 테스트: Xcode에서 `⌘U`, 또는
```bash
xcodebuild test -project ios/Daisy.xcodeproj -scheme Daisy -destination 'platform=macOS'
```

## AI 에이전트에게

### 작업 범위
- **`ios/` 폴더 안만 수정해요.** 다른 폴더(`web/`, `server/`, `infra/`)나 다른 레포(`sample-*`)는 읽기만 해요
- SPEC.md의 M 항목부터 만들어요. S 항목은 사람이 요청할 때만
- 새 SPM 의존성, 새 타깃, 최소 OS 변경, 번들 ID · 서명 설정 변경은 **사람 확인 없이 하지 않아요**

### 명세 보고 (가장 중요)
백엔드 계약이 아직 확정되지 않았어요. 그래서 에이전트가 **API를 추측해서 코드를 쓰면 반드시 기록**해요.
1. 서버에 필요한 API · 필드 · 이벤트가 SPEC.md에 없으면, 코드를 쓰기 전에 **SPEC §6에 `(가칭)` 🆕 항목으로 먼저 추가**해요
2. 추가하거나 바꾼 SPEC 항목은 작업 끝에 **사람에게 목록으로 보고**해요 (ID, 무엇을, 왜)
3. SPEC §6-7 모델과 `Core/Models`가 어긋나면 안 돼요. 하나를 바꾸면 다른 하나도 같이 바꿔요
4. 확정된 이름(`(가칭)` 표시 없음)은 사람 확인 없이 바꾸지 않아요

### 목업
- 실서버 API가 없는 동안에는 `MockAPIClient`와 `Mock/Fixtures`로 만들어요
- 목업 코드에는 `// MOCK:` 주석, 목업 모드 화면에는 MOCK 배지. **목업을 숨기지 않아요** (발표 규칙)
- 픽스처 JSON은 SPEC §6-7 모양 그대로

### 하지 말 것
- 토큰 · APNs 키 · 비밀번호를 코드나 픽스처에 넣지 않아요. 데모 계정 정보도 커밋하지 않아요
- GitHub · 클라우드 API를 앱에서 직접 부르지 않아요 (모든 데이터는 Daisy 백엔드 경유)
- `xcodebuild archive`, App Store Connect 업로드, TestFlight 배포는 사람이 해요
