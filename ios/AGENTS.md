# AGENTS.md — ios/ (native app for iOS and macOS)

Owner: 박승준 (`Seungjun1127`). Status: v1 (2026-09-29).

Follow the root `AGENTS.md` first. This file adds rules for `ios/` only and never loosens the root hard rules. The product spec, screen list, and every request to the backend are in [`SPEC.md`](./SPEC.md) (Korean). **Read `SPEC.md` before any task here.**

## 1. What this area is

A native SwiftUI app that shows Daisy deployments on iPhone and Mac: **view, approve, notify.**

- Screens (M): overview of what runs where, deployment list and detail, plan approval, commits and pipelines, settings (`SPEC.md` §2)
- The app never starts deployments, registers or deletes environments, or calls GitHub, cloud APIs, or Terraform directly. All data comes through the Daisy server API (`SPEC.md` §4).
- Distribution goal: a public TestFlight link that judges install during the demo. The first build goes to Beta App Review on **10/1** (`SPEC.md` §5).

## 2. Contracts this area depends on

`ios/` provides no contract to other areas. It consumes these, all owned by server (하은현, 김승환):

| Contract | Where we track our needs | Status |
|---|---|---|
| REST API paths | `SPEC.md` §6-2, §6-4 | Decided by server on 9/29 (PR #1 review). D2: A-01, A-02, A-04. D3: the rest |
| Response fields | `SPEC.md` §6-7 | `Plan` decided (server `PlanSummary`). Other fields `(가칭)` until server publishes OpenAPI |
| SSE channels and events | `SPEC.md` §6-3 | Names decided. Server ships SSE on D3; poll every 5 s until then |
| Auth, demo viewer account, dev server | `SPEC.md` §6-1 | Decided: Bearer only (no cookies). Ships D2 |
| HTTPS public address | `SPEC.md` R-04 | Decided 9/29: purchased domain + HTTPS, set up by server by 9/30 afternoon |
| Push device registration and APNs sending | `SPEC.md` §6-5 | Paths decided; unregister is `DELETE /devices` with the token in the body. Server does APNs only if time allows; use local notifications until then |
| CI event payload fields | `SPEC.md` §7 | `(가칭)`: server (하은현) forwards it to CI (김도영) as an issue |

These belong to server, so they are tier 3 in root §6: the server owner decides names and shapes. `SPEC.md` §6-0 is the current status table.

## 3. How to work here

1. Before writing code that talks to the server, find the endpoint, field, or event in `SPEC.md` §6.
2. **If it is not there, add it to `SPEC.md` §6 first** as a `(가칭)` 🆕 row (ID, method and path, fields, why the app needs it). Then write the code against that entry.
3. Keep `SPEC.md` §6-7 and `Daisy/Core/Models` identical in shape. If you change one, change the other in the same commit.
4. Do not rename anything that has no `(가칭)` marker without asking your human; it has been agreed with server.
5. When the server publishes or changes the real contract, run the root §8 contradiction check against `SPEC.md`. Adapt the app to the server's decision, and remove `(가칭)` from entries that now match.
6. At the end of the task, list every `SPEC.md` entry you added or changed (ID, what, why) in your report, and draft the server issue for each new one (root §9).

## 4. No mocks

The app always talks to a real server. There is no mock mode, fake API client, or hard-coded data in the app.

- If the server API a screen needs does not exist yet, build the layout only and report which `SPEC.md` ID it is waiting for.
- Sample values are allowed only inside `#Preview` blocks and `DaisyTests`. Code under `App/`, `Features/`, and `Core/` never references them.
- Sample JSON follows `SPEC.md` §6-7 exactly and contains no real tokens, passwords, or URLs with credentials.

## 5. Stack and structure

- SwiftUI multiplatform, one app target for iPhone, iPad, and native macOS (iOS 18+, macOS 15+). Swift 6 with strict concurrency. Xcode 27.
- No third-party packages. `URLSession` + `async/await` + `Codable`. SSE is parsed from `URLSession.bytes`, with 5-second polling as the fallback. Tokens live in the Keychain. Push uses APNs.

```
ios/
├─ AGENTS.md
├─ SPEC.md
├─ Daisy.xcodeproj
├─ Daisy/
│  ├─ App/            entry point, root layout (sidebar at width ≥ 700, tabs below), Sidebar, dependency wiring
│  ├─ Features/       one folder per screen: Overview, Deployments, Approvals, History, Settings (View + Store each)
│  ├─ Core/           API, Models, Realtime, Auth, Push
│  ├─ DesignSystem/   materials, glass buttons and segmented control, PageHeader/PageScaffold, cards, badges
│  └─ Resources/
├─ DaisyTests/        model decoding, SSE parser, store state transitions
└─ DaisyWidgets/      (S) widgets and Live Activity
```

## 6. Conventions

- Types `UpperCamelCase`, everything else `lowerCamelCase`. Screens are `{Feature}View`; their state is a `@Observable` `{Feature}Store`.
- A view used by one screen lives in that `Features/{Feature}/`. A view used by two or more screens moves to `DesignSystem/`.
- Decode JSON with `convertFromSnakeCase`. Every enum decoded from a server string has an `unknown` case, so a new server value never crashes the app.
- Map the server error envelope to `APIError`. `401 UNAUTHENTICATED` → login screen. `409 STATE_CONFLICT` → reload the latest state. A viewer account gets `403` on approval; show it as "읽기 전용 계정".
- **Layout adapts to available width, not to the platform.** `RootView` shows the custom sidebar at width ≥ 700 (iPad, Mac; the Mac window's minimum width is 820) and system tabs below that (iPhone). Inside a screen, use `AdaptiveGrid` and `cardStyle()` so cards form one column on a phone and several on wide screens. Do not branch on `horizontalSizeClass`; it does not exist on macOS.
- `#if os(iOS)` / `#if os(macOS)` only for platform-only capabilities (keyboard type, menu bar, haptics), and only in `App/` and `DesignSystem/`, never in feature logic.
- Test in this order: iPhone, then Mac, then iPad. iPad only needs to not break.

### Design (owner decision, 9/30)

Materials, the sidebar, and motion copy the owner's AfterPlan Mac app (`~/Github/AfterPlan/docs/design/macos-design.md`); buttons follow the owner's Craft reference. Keep to these; change them only when your human asks.

- **Layers.** Sidebar: `SidebarBackground()` (Mac: `NSVisualEffectView` `.hudWindow`, behind-window blending, follows window active state, no tint). Content: `.contentSurface()` (Mac: `.underWindowBackground`, translucent; Reduce Transparency makes it opaque). Lists and forms use `.onContentSurface()` so they do not paint their own background. No line between sidebar and content; the change of material is the boundary.
- **Window (Mac).** Unified toolbar without a title, toolbar background hidden, only the sidebar button on the left (⌃⌘S). The settings gear sits alone at the bottom left of the sidebar.
- **Sidebar rows.** 15 pt text, 16 pt icon in a 22 pt frame, 36 pt high, 10 pt inset. Selected: `.fill.tertiary` rounded 8 plus semibold; hover: `.fill.quinary`. No accent color. The tint moves with `.spring(response: 0.32, dampingFraction: 0.86)` via `matchedGeometryEffect`; weight changes at once; Reduce Motion drops the spring. Width 240 by default, 190–420 by dragging the edge, remembered.
- **Screens.** Every root screen uses `PageScaffold(title, subtitle:, trailing:)`: a `title2` semibold title on the left and the screen's controls on the right. Pushed detail screens keep the system navigation title.
- **Buttons.** Icon-only actions use `.buttonStyle(.glassCircle)`; text actions and menus use `.glassCapsule`; choices use `GlassSegmented`. They use Liquid Glass on iOS 26 / macOS 26 and a material with a hairline below that. Destructive actions use `role: .destructive`.
- **Cards.** `cardStyle()`: corner 12, `.fill.quaternary`, hairline `.separator` border, `.fill.tertiary` on hover.
- **Taking from the web design (Figma).** Take **wording only**: screen and menu names, labels, status names, messages, notation. Colors, shapes, radius, fonts, and layout stay with this app's design above, even where Figma says otherwise (no-pill, radius ≤ 4, IBM Plex, yellow button). For each web icon, use the closest SF Symbol: cloud → `cloud`, play → `play`, server → `server.rack`, clock → `clock`, terminal → `apple.terminal`, signal → `cellularbars`, settings → `gearshape`.

### Match the web's feature UX

The app and the web show the same deployments, so a feature that exists in both follows the web's flow, wording, and notation (for example resource counts as `+create ~update -delete`). Before building or changing such a flow:

1. Look for the web's current version even if it is not on `main`: `git fetch --all --prune`, then `git branch -r`, `gh pr list --state all`, and `git log origin/<branch> -- web/` or `git show origin/<branch>:web/...`.
2. If there is no web code yet, read the Figma file `5nqU4xotMh5jcsaDqOcTST`: page `0:1` 와이어프레임 v1.0 (screens W-00–W-13 with NOTE frames, and frame `80:3366` "Memo · Apple 앱 참고" written for this app) and page `2:4` 디자인 시스템. The page listing only shows `2:4`; open the others by id. Then the Notion User Flow Chart.
3. If the app needs to differ (small screen, approve-only scope), keep the difference small and note it in `SPEC.md`. If the web and `SPEC.md` contradict each other, run the root §8 contradiction check; do not silently follow either.
- User-facing strings are Korean, 해요체.
- Show AI cost as an estimate: label it "추정" and show the exchange rate the server applied.
- When `approval.required` arrives again for a deployment whose `attempt` did not change, the server re-ran a stale plan. Show the approval card again with the same "시도 n/3" and say the plan was refreshed.
- Show `attempt` as "시도 n/3". It counts the first generation, so it starts at 1 and the AI fixes at most twice. Never label it as a retry count.

## 7. Commands

```bash
open ios/Daisy.xcodeproj

# Build without signing (what agents should run to verify)
xcodebuild -project ios/Daisy.xcodeproj -scheme Daisy -destination 'generic/platform=macOS' build CODE_SIGNING_ALLOWED=NO
xcodebuild -project ios/Daisy.xcodeproj -scheme Daisy -destination 'generic/platform=iOS' build CODE_SIGNING_ALLOWED=NO

# Tests run on macOS with ad-hoc signing
xcodebuild test -project ios/Daisy.xcodeproj -scheme Daisy -destination 'platform=macOS' CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM=""
```

Set the server address (dev or demo server) in the app's settings screen and log in.

## 8. Ask your human first

- Adding a Swift package, a new target, or an extension; changing the minimum OS, bundle ID, signing, capabilities, or entitlements
- `xcodebuild archive`, uploading to App Store Connect, TestFlight distribution (the human does these)
- Anything involving the APNs `.p8` key, demo account credentials, or the Apple Developer account

## 9. Decisions log

Tier per root §6. Tier 1 entries are final for this area.

| Date | Decision | Why | Tier |
|---|---|---|---|
| 9/29 | SwiftUI multiplatform, one target for iOS and macOS | One codebase for both platforms, so adding macOS costs little | 1 |
| 9/29 | ~~Minimum iOS 17 · macOS 14~~ (replaced 9/30, see below) | Needed for `@Observable` | 1 |
| 9/29 | No third-party packages to start | Same "minimal stack, add only when blocked" principle as ADR-006 | 1 |
| 9/29 | No mock mode; the app always uses the real server | Owner decision. Consequence: app progress depends on server API dates (`SPEC.md` R-08) | 1 |
| 9/29 | SSE parsed with `URLSession.bytes`, 5-second polling fallback | Uses the same SSE endpoints as web, so server builds nothing app-specific | 1 |
| 9/29 | Tokens stored in the Keychain | Tokens must not sit in UserDefaults | 1 |
| 9/30 | Xcode project written by hand with synchronized folders (`PBXFileSystemSynchronizedRootGroup`); no XcodeGen or Tuist | New files under `Daisy/` and `DaisyTests/` are picked up automatically, so agents never edit `project.pbxproj` to add a file | 1 |
| 9/30 | Bundle ID `com.teamdaisy.daisy`, version 0.1.0, `ITSAppUsesNonExemptEncryption = NO` | Needed for App Store Connect; the encryption flag skips the export-compliance prompt on every TestFlight upload | 1 |
| 9/30 | Lists decode as `Page<T>` (`{ items, next_cursor }`), including A-02 | v0.1 common list rule; confirm when server publishes OpenAPI | 3 (`(가칭)`) |
| 9/30 | **One responsive codebase, not separate native apps.** Minimum iOS 18 · macOS 15; width-based layout and `AdaptiveGrid` for cards | One developer, three days: each screen is built once. The phone (judges) and Mac (presenter) get the same app shaped to their width | 1 |
| 9/30 | Custom sidebar at width ≥ 700 instead of `.sidebarAdaptable` | The system sidebar cannot take the HUD material, the no-divider boundary, or the tint animation from the AfterPlan design | 1 |
| 9/30 | Design: AfterPlan materials, sidebar, and motion; Craft-style glass buttons; `PageScaffold` headers | Owner's design references (Design section above) | 1 |
| 9/30 | Feature UX matches the web (flow, wording, `+/~/-` notation); check web branches and PRs before building a shared flow | Owner decision: one product on two clients | 1 |
| 9/30 | App icon: the owner's daisy logo. iOS gets a full-bleed opaque 1024 square; macOS gets the logo inside Apple's rounded-rect grid (824 of 1024, radius 185.4, soft shadow) at 16–1024. The sidebar header uses the same logo (`AppLogo`) | Owner's asset. The source is 200×200, so replace it with a 1024+ original before release | 1 |
| 9/30 | From Figma, take wording only; keep this app's colors and shapes; icons are the nearest SF Symbols | Owner decision. 도영's memo asked for web shapes (radius ≤ 4, no pills) and the owner chose the app's own look | 1 |
| 9/30 | Menu and wording follow the web: 개요 · 배포 · 승인 · 이력 · 설정; status labels 대기 중 · 배포 중 · 성공 · 실패 · 주의 · 롤백됨; `리소스 +6 ~0 −0`; W-00 login and error messages | Same product on two clients | 1 |
| 9/30 | Tests use Swift Testing; sample JSON lives only in `DaisyTests` | No mock data in the app (§4) | 1 |
| 9/29 | The app does not start deployments or change infrastructure | Keeps the app inside ADR-007 and keeps the server work small | 1 |
| 9/29 | Widen ADR-007: add overview, commit history, macOS | Proposed in `SPEC.md` §1-2; needs the team meeting | 4 (`(가칭)`) |
| 9/29 | Requests to server and CI | `SPEC.md` §6–§7; the server and CI owners decide names and shapes | 3 |
| 9/29 | Server accepted the §6 names; unregister device with `DELETE /devices` + body | Token in a URL path leaks into access logs (server's request). Recorded in `SPEC.md` §6-0 | 3 (decided by server) |
| 9/29 | Until server ships SSE and APNs (D3 or later): poll every 5 s and show local notifications | Agreed with server; keeps the app working on D2 | 1 |
