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
| HTTPS public address | `SPEC.md` R-04 | `[미정]`: team meeting 9/29 |
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

- SwiftUI multiplatform, one app target for iOS 17+ and macOS 14+. Swift 6 with strict concurrency. Xcode 27.
- No third-party packages. `URLSession` + `async/await` + `Codable`. SSE is parsed from `URLSession.bytes`, with 5-second polling as the fallback. Tokens live in the Keychain. Push uses APNs.

```
ios/
├─ AGENTS.md
├─ SPEC.md
├─ Daisy.xcodeproj
├─ Daisy/
│  ├─ App/            entry point, root view (iOS TabView / macOS NavigationSplitView), dependency wiring
│  ├─ Features/       one folder per screen: Overview, Deployments, Approvals, History, Settings (View + Store each)
│  ├─ Core/           API, Models, Realtime, Auth, Push
│  ├─ DesignSystem/   shared views: status badge, environment icon, commit hash label
│  └─ Resources/
├─ DaisyTests/        model decoding, SSE parser, store state transitions
└─ DaisyWidgets/      (S) widgets and Live Activity
```

## 6. Conventions

- Types `UpperCamelCase`, everything else `lowerCamelCase`. Screens are `{Feature}View`; their state is a `@Observable` `{Feature}Store`.
- A view used by one screen lives in that `Features/{Feature}/`. A view used by two or more screens moves to `DesignSystem/`.
- Decode JSON with `convertFromSnakeCase`. Every enum decoded from a server string has an `unknown` case, so a new server value never crashes the app.
- Map the server error envelope to `APIError`. `401 UNAUTHENTICATED` → login screen. `409 STATE_CONFLICT` → reload the latest state. A viewer account gets `403` on approval; show it as "읽기 전용 계정".
- `#if os(iOS)` / `#if os(macOS)` only in `App/` and `DesignSystem/`, never in feature logic.
- User-facing strings are Korean, 해요체.
- Show `attempt` as "시도 n/3". It counts the first generation, so it starts at 1 and the AI fixes at most twice. Never label it as a retry count.

## 7. Commands

```bash
open ios/Daisy.xcodeproj
xcodebuild test -project ios/Daisy.xcodeproj -scheme Daisy -destination 'platform=macOS'
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
| 9/29 | Minimum iOS 17 · macOS 14 | Needed for `@Observable`, and covers most judges' devices | 1 |
| 9/29 | No third-party packages to start | Same "minimal stack, add only when blocked" principle as ADR-006 | 1 |
| 9/29 | No mock mode; the app always uses the real server | Owner decision. Consequence: app progress depends on server API dates (`SPEC.md` R-08) | 1 |
| 9/29 | SSE parsed with `URLSession.bytes`, 5-second polling fallback | Uses the same SSE endpoints as web, so server builds nothing app-specific | 1 |
| 9/29 | Tokens stored in the Keychain | Tokens must not sit in UserDefaults | 1 |
| 9/29 | The app does not start deployments or change infrastructure | Keeps the app inside ADR-007 and keeps the server work small | 1 |
| 9/29 | Widen ADR-007: add overview, commit history, macOS | Proposed in `SPEC.md` §1-2; needs the team meeting | 4 (`(가칭)`) |
| 9/29 | Requests to server and CI | `SPEC.md` §6–§7; the server and CI owners decide names and shapes | 3 |
| 9/29 | Server accepted the §6 names; unregister device with `DELETE /devices` + body | Token in a URL path leaks into access logs (server's request). Recorded in `SPEC.md` §6-0 | 3 (decided by server) |
| 9/29 | Until server ships SSE and APNs (D3 or later): poll every 5 s and show local notifications | Agreed with server; keeps the app working on D2 | 1 |
