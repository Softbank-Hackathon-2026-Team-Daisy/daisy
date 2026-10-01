# AGENTS.md — Team Daisy (global rules for every agent)

You are a coding agent working for one member of Team Daisy at SoftBank Hackathon 2026 in Korea (Term 1 prelims). This file is the team-wide contract that every agent in every area follows. Read all of it at the start of a session, then read the `AGENTS.md` of the area you are about to change.

- Status: v1.2 (2026-09-30 evening, synced with the 9/29 meeting, every area's decisions logs, PR answers, and Slack up to 20:35; source list: `ios/BOARD.md` on PR #8). Owner: team lead (김도영). Change it only by PR with team review.
- This file is written in English for precision. **Everything you write for humans is in Korean** (see §11).
- Some area folders may still have a `CLAUDE.md` instead of an `AGENTS.md`. Treat it as that area's `AGENTS.md`. Where it says "root `CLAUDE.md`", it means this file.

---

## 1. Mission

**Ship a system that works end to end by 2026-10-03 (Sat) 24:00 KST.** Everything in this repo serves that goal. The final live demo is on 10/4.

"Works end to end" means this path runs for real, at least once, on the sample apps:

```
main merge → GitHub Actions builds the image (tag = commit hash)
→ user selects target environments (on-prem · AWS · GCP) in the web UI
→ AI generates Terraform per environment from deploy.yaml (or reuses a validated script, 0 AI calls)
→ validate · plan · risk check (on failure the AI fixes it, max 3 attempts)
→ a human approves the plan → parallel apply per environment → public URLs
```

How to prioritize under the deadline:

- Work on the demo path before anything else. Priority M (must) before S (should).
- Make the smallest change that works. Do not add abstractions, options, or features nobody asked for.
- Keep `main` demoable at all times. A half-finished feature stays on its branch.
- If a task will not make it, tell your human early and name the fallback. The Notion PoC plan lists a fallback for each PoC.

## 2. Who you work for

Find out which teammate you are working for before you change anything (`gh api user --jq .login`, or `git config user.name`), and match them to the table in §5. **Their areas define what you may decide without the team.** If you cannot tell, ask.

## 3. Instruction priority

When instructions conflict, follow the higher item:

1. **Hard rules** (§4). Nothing overrides them.
2. **Team decisions**: ADRs and shared contracts without a `(가칭)` or `[미정]` marker (§12). Only a team meeting changes them.
3. **Your human's instructions in this session**, within their authority (§6). If they ask for something outside it, say which rule applies and offer the issue or meeting path (§9, §6). Do not comply silently, and do not refuse without offering that path.
4. **The `AGENTS.md` of the area you are working in.** The area owner's decisions win for that area.
5. **This file's defaults.**
6. **Specs and docs.** Anything marked `(가칭)` or `[미정]` is a working assumption, not a decision.

If two sources at the same level conflict, stop and ask your human.

## 4. Hard rules

These exist because a mistake here costs money, leaks secrets, or breaks the demo for all six people.

1. **Never commit secrets**: `.env`, `*.tfvars`, `*.tfstate`, cloud key files, API keys, tokens, `.p8` keys, demo account passwords. If one gets committed, tell your human right away; the key must be revoked, because deleting the commit does not remove it from history.
2. **Never run commands that create, change, or delete real infrastructure** (`terraform apply`, `terraform destroy`, cloud CLI create/delete) without your human's explicit confirmation in this session. `terraform validate` and `terraform plan` are fine.
3. **Never push to `main`, and never force-push a branch someone else uses.** Every change goes through a PR.
4. **Never edit files in an area you do not own**, in this repo or the sample repos. Open an issue instead (§9). The only exception: the owner explicitly asks you to in that issue or PR.
5. **Never change a team decision or shared contract on your own** (§5-2, §12). Propose it with `(가칭)` and take it to the team (§6).
6. **Label every mock.** `// MOCK:` in code and a visible badge on screen. The presentation rules forbid hiding mocks. Areas decide whether they use mocks at all (`web/` keeps them in `src/mocks/`; `ios/` has one offline sample mode with a badge on every screen); report every remaining mock to your human before the 10/3 submission.
7. **Never report work as done without verifying it** (§7 step 6). If a test fails or you skipped a step, say so.

## 5. Areas and owners

### 5-1. Areas

| Area | Where | Owner (GitHub) |
|---|---|---|
| Team lead: scope, schedule, root docs, ADR records | `AGENTS.md`, `README.md`, `CONTRIBUTING.md`, `docs/` | 김도영 (`kimdoyoung1110`) |
| Web dashboard (full flow) | `web/` | 김도영 (`kimdoyoung1110`) |
| Native app (iOS · macOS). Scope is under team decision (§12-4, ADR-007) | `ios/` | 박승준 (`Seungjun1127`) |
| Server: API, deployment state machine, approvals, `terraform apply` execution, locks, SSE, CI webhook, history · rollback | `server/` | 하은현 (`gkdmsgus`) |
| Server: `deploy.yaml` parsing, AI Terraform generation, validate/fix loop, common Terraform CLI runner, script reuse, AI cost | `server/` | 김승환 (`7SH7`) |
| On-prem Terraform module, Docker runtime, tunnel | `infra/modules/onprem/` | 황지환 (`jihwan77`) |
| Cloud Terraform modules (GCP, AWS), state backends, Jenkins runner prototype | `infra/modules/gcp/`, `infra/modules/aws/`, `infra/jenkins/`, `infra/scripts/` | 임채준 (`dlacowns21`) |
| CI for this repo | `.github/workflows/` | 김도영 |
| Sample monolith app (HelloCalc) and its image pipeline (N-01) | repo `sample-monolith` | 박승준 (app), 김도영 (Actions) |
| Sample MSA app (HelloCalc MSA: one frontend + one backend container) | repo `sample-msa` | 박승준 |
| Org issue/PR templates, org profile | repo `.github` | 김도영 |

`server/` has two owners. For other areas it is one area. Inside `server/`, the two owners settle boundaries between themselves.

### 5-2. Shared contracts

A shared contract is anything another area builds against. Each has a **provider** who decides its shape, and **consumers** who depend on it.

| Contract | Provider (decides) | Consumers | Changed by |
|---|---|---|---|
| `deploy.yaml` schema (§12-5) | whole team | all | team meeting only |
| REST API: paths, payloads, errors, auth. **Single source: the server's OpenAPI** (springdoc `/v3/api-docs`); Notion "Backend API Endpoint" is the agreement record | server (하은현; AI-side payloads 김승환) | web, ios | provider, after notifying consumers |
| SSE events: channels, names, payloads | server (하은현) | web, ios | provider, after notifying consumers |
| Deployment state and step names (decided 9/30, §12-4) | server | web, ios | provider, after notifying consumers |
| Terraform module input variables | infra (황지환, 임채준) | server AI (김승환) | provider, after notifying consumers |
| CI → deploy service event payload | CI (김도영) | server (하은현) | provider, after notifying consumers |

## 6. Decision authority

Before making any decision, classify it. Owners decide their own areas immediately so nobody waits on a meeting, and only real cross-team questions reach the meeting.

| Tier | What it covers | What you do |
|---|---|---|
| **1. Own area** | Inside your human's area and invisible to other areas: internal structure, file layout, UI, internal naming, tests, libraries used only in that area | **Decide now.** It is final (`확정`) immediately; no meeting. Add one line to the area's decisions log (below), and draft a one-line Slack note for your human to share. |
| **2. Contract you provide** | A change to a contract your human's area provides (§5-2) | Decide, then tell each consumer area about the change before you merge: an issue, or a Slack message your human posts. If a consumer reports a conflict you cannot settle in the issue, it becomes tier 4. |
| **3. Another area** | Anything another area owns, including a contract you only consume | **The owner decides.** Write your need into your spec with `(가칭)` and send it to the owner as an issue or a Slack request (§9). No meeting unless the owner and your human disagree; then it becomes tier 4. Keep working on parts that do not depend on it. |
| **4. Team** | The `deploy.yaml` schema; any `[미정]` item in §12; ADRs; scope or schedule; a contradiction the owners do not settle in the issue | **Do not decide.** Write it with `(가칭)`, open a `[결정]` issue, and tell your human it needs the team meeting (daily 21:00–22:00 KST). Keep working on parts that do not depend on it. |

Rules that follow from this:

- **The area owner has priority inside their area.** If their recorded decision conflicts with what you would prefer, theirs wins. You may ask them to reconsider in an issue.
- **Anything you propose that someone else owns stays `(가칭)`** until the owner accepts it or the meeting decides. Then remove the marker and use the final name.
- Markers: `(가칭)` = provisional name or shape; `[미정]` = undecided team item; no marker = decided.
- **Decisions log.** Every area `AGENTS.md` keeps a table `| Date | Decision | Why | Tier |`. Other agents read it during the contradiction check (§8), so record tier 1 and 2 decisions there, not only in chat. Tell your human when a decision is big enough for a Notion ADR (for example, adding a dependency, per ADR-006).

## 7. Workflow for every task

1. **Orient.** Read this file, the area `AGENTS.md`, and the specs the task touches. Check `git status` and your branch.
2. **Check for contradictions** (§8) if the task touches or depends on another area or a shared contract.
3. **Classify every decision** the task needs (§6).
4. **Spec first.** Write or update the area's `SPEC.md` for the feature before implementing it. For anything larger than a small fix, also state a short plan to your human. Name the files you will touch; they must all be in your human's area.
5. **Implement** in small steps on a branch named per §11.
6. **Verify.** Build, run the tests, and run the thing. For infra, `terraform validate` and `plan` only (§4). Paste the actual result, not a summary of what should happen.
7. **Reconcile the spec.** Compare what you built with `SPEC.md` and update the spec so it matches, in the same PR.
8. **Report** in the format of §10, then open the PR.

## 8. Contradiction check

Before implementing anything that crosses an area boundary, look for conflicts in:

- this file and the other area's `AGENTS.md` (especially its decisions log) and specs
- open issues and PRs: `gh issue list`, `gh pr list` (in this repo and the sample repos)
- the other area's code on `main`

If you find a contradiction, work out which case it is:

- **Intended by the other side** (it is in their decisions log, spec, or merged code and looks deliberate): their choice wins in their area. Adapt your side if you can. If you cannot, open an issue asking them to reconsider, with the impact on your area.
- **Nobody knew** (not recorded anywhere, looks like drift): open an issue to the owner with the evidence (file paths, lines, links). The owner decides whether to change direction.
- **It involves a team decision, or both sides must change, or the owners disagree:** this is tier 4. Tell your human that a team meeting is needed and draft the agenda item as a `[결정]` issue.

In every case, tell your human. Never quietly code around a contradiction, and never "fix" the other side yourself.

## 9. Changes outside your area: request, do not implement

When your task needs another area to change code or add a feature, do not implement it there, and do not open a PR in their folder. Request it with enough detail that the owner's agent can act on it without asking:

- **Issue** (default): anything that needs tracking, a spec, or a decision.
- **Slack**: a quick question or a small request. Draft the message; your human posts it. If it turns into real work, move it to an issue.

For issues:

1. Search open issues first so you do not file a duplicate.
2. Draft the issue in Korean using the structure below, show it to your human, and file it when they say yes.
3. Assign the area owner. Title prefix: `[작업]` for a request, `[결정]` for a contradiction or a team decision.

```
제목: [작업] [{대상 파트}] {요청 한 줄} (가칭)

## 파트
{대상 파트} ← 요청: {요청 파트} ({요청자})

## 상황
무엇을 하다가 왜 필요해졌는지 3~5줄

## 요청 명세 (가칭)
정확한 경로·필드·타입·예시 JSON·동작. 이름은 받는 쪽이 정해요.

## 모순 확인
확인한 곳과 결과: 없음 / 있음 (의도된 것 같음 · 몰랐던 것 같음) + 근거

## 완료 기준
어떻게 되면 요청 파트가 쓸 수 있는지

## 영향과 기한
막히는 데모 흐름, 필요한 날짜

## 그동안 요청 파트는
기다리는 동안 하는 일 (대안)

Refs: {관련 PoC · ADR · 스펙 링크}
```

## 10. Reporting to your human

End every task with a short report in Korean:

- **변경**: files changed and why
- **결정 (확정)**: tier 1 and 2 decisions you made, and where you logged them
- **결정 필요 (가칭)**: tier 3 and 4 items with issue links; mark tier 4 items "회의 필요"
- **이슈**: issues you filed or drafted
- **검증**: commands you ran and their real results
- **남은 일**: what is left and what blocks it

## 11. Conventions

- **Language.** Commit descriptions, PR text, issues, docs, and messages to humans are in Korean, in the 해요체 style. Code identifiers are in English. Code comments follow the file's existing language.
- **Branches.** `{part}/{type}-{short-desc}`. part: `web`, `ios`, `server`, `infra`, `docs`, `ci`. type: `feat`, `fix`, `refactor`, `docs`, `chore`, `test`.
- **Commits.** Conventional Commits with the part as scope: `feat(server): ...`. Add `Refs: N-03` when a PoC is involved.
- **PRs.** Fill in the org PR template. Squash merge only; merged branches are deleted automatically. Aim for under 300 changed lines. Changes to a shared contract add the consumer owners as reviewers.
- **Merging.** `unibloom` needs one approval (plus the CODEOWNERS team for `server/` and `infra/`), and pushing a new commit dismisses earlier approvals. The `protect-main` ruleset has no bypass; only 김도영 is an org owner. `sample-monolith` and `sample-msa` allow self-merge after a PR. On 10/3–10/4 self-merge is allowed everywhere.
- Full details: `CONTRIBUTING.md`.

## 12. Project reference

### 12-1. What we are building

**Unibloom** — **AI 기반 온프레미스·퍼블릭 클라우드 원터치 배포 시스템** ("One Action, Infinite Clouds"). The service was renamed from Daisy on 10/1; the team is still Team Daisy. The user picks target environments, and AI generates and validates Terraform per environment so the same image deploys to on-prem and public clouds at the same time.

- Core idea: **portability**, the same image in the same state everywhere.
- Say "퍼블릭 클라우드", not "하이퍼스케일러" (the target includes small cloud providers).
- The AI is used only where judgment is needed (generating and fixing Terraform). Execution is done by validated code and Terraform. **Every infrastructure change needs human approval.**

### 12-2. Deployment flow (7 steps)

1. **Connect the app (once):** `Dockerfile` + `deploy.yaml` in the user's repo.
2. **Change code:** PR → merge to `main`.
3. **Build the image:** GitHub Actions builds and tests, tags with the **commit hash**, pushes to the registry, and sends an event to the deploy service.
4. **Select environments** in the UI (on-prem, AWS, GCP; several at once). Only GitHub repos are an input; source upload is out of scope (9/30).
5. **Generate Terraform (AI)** per environment. If a validated script exists, only swap the image tag (0 AI calls).
6. **Validate and fix:** `validate` → `plan` → risk check. On failure the AI reads the log and fixes it, **3 attempts in total per environment** (the first generation counts). An environment that runs out stops and the user is notified; **the other environments keep going**.
7. **Approve and apply:** a human approves the plan → **parallel `apply`** per environment. State is stored separately per environment. A **rollback** is a new deployment of an earlier successful commit with its validated script, and it also needs plan approval.

### 12-3. Repos

| Repo | Purpose |
|---|---|
| `unibloom` (this repo; renamed from `daisy` on 10/1, old URLs redirect) | Our deployment system: `web/`, `ios/`, `server/`, `infra/modules/{onprem,gcp,aws}/`, `docs/`, `.github/workflows/` |
| `sample-monolith` | Deployment target that mimics a user's repo: HelloCalc (Go) + N-01 image pipeline |
| `sample-msa` | Deployment target: two-service MSA |
| `.github` | Org-wide issue and PR templates, org profile |

The sample repos stand in for a user's app. Do not mix their code into `unibloom`. Clone and work in `unibloom` for all system work; clone a sample repo only when working on it.

### 12-4. Decided (ADR summary; full records in Notion)

| ADR | Decision |
|---|---|
| 001 | Roles: web (FE, BE) / infra (on-prem, cloud) |
| 002 | Topic: AI one-touch deployment to on-prem and public clouds |
| 003 | IaC is **Terraform** |
| 004 | App input: GitHub repo + `main` merge + GitHub Actions |
| 005 | On-prem runtime is **Docker** |
| 006 | Web is a **React + Vite SPA** (not Next.js). Start with a minimal stack; add libraries only when blocked, and record why |
| 007 | Web runs the full flow; the Swift app does approval, progress, and push only. `ios/` proposes widening it to the full wireframe (`ios/SPEC.md` §1-1, §8), which conflicts with `web/SPEC.md` §1-1; **team meeting item**. Until the team decides, this line stands |

**Decided in the 9/29 meeting (Notion ADR entries pending):** backend is **Spring Boot**; public access uses a **purchased domain with HTTPS** (server owners); roles: web is 김도영, the Swift app is 박승준; build features first and add visualization (e.g. loading screens) afterwards; the presenter is chosen on 10/3; part meetings use Slack huddles (backend daily 18:00–19:00).

**Decided by the owning area** (decisions logs, PR answers, Slack; one line each, details in the area files):

- **API and server** (하은현 · 김승환)
  - One **Bearer** token for REST and SSE; GitHub only connects repos (no OAuth login). Demo accounts (`viewer`) can read but get 403 on approve.
  - JSON is `snake_case`; times are ISO 8601 UTC; KRW amounts are integers; states and steps are strings and unknown values must not crash clients. Single source of the contract: the server's OpenAPI.
  - Deployment state, two layers. Whole deployment: `queued · running · awaiting_approval · succeeded · partially_succeeded · failed · cancelled`. Per environment: `waiting · generating · validating · awaiting_approval · applying · verifying · succeeded · failed · cancelled`. Steps: `generate · validate · plan · risk_check · apply · health_check`.
  - `attempt` counts per environment, 3 in total including the first generation; one environment failing does not stop the others; a stale re-plan does not count and needs a new approval. Cancel works before apply; after that it is a stop request.
  - SSE: `id` = per-channel `seq` starting at 1, reconnect with `Last-Event-ID`, heartbeat every 15 s. Clients poll every 5 s until SSE ships (D3).
  - Paths: start a deployment with `POST /projects/{id}/deployments`; environment picker `GET /projects/{id}/targets` is separate from `targets/status`; deleting a project only disconnects it. Image identity is `image_digest`, not only the tag.
  - Rollback is in scope: a new deployment (`kind: "rollback"`) from an earlier successful commit and its validated script, per environment, with plan approval.
  - Out of the v0.1 draft: source upload, analysis, IR editing, recommendations, observability, canary. Manifest errors use `MANIFEST_INVALID`.
  - Stack: Spring Boot 3.5 · Java 21 · Postgres job queue · Flyway migrations. 김승환 produces the plan detail and the generated Terraform files; 하은현 exposes them.
  - AI cost: USD summed per deployment, converted at a fixed rate, always shown as an estimate with the rate.
- **Web** (김도영): React + Vite + TypeScript, `react-router`, CSS variable tokens (no UI kit); labeled MSW mocks in `src/mocks/`; SSE via `fetch` streaming. Wireframe changes 9/30: upload (W-02b) removed, W-05b "○○만 다시 시도" (no "skip and continue"), W-12 AI usage per deployment, W-14 Mac download.
- **App** (박승준): one SwiftUI codebase for iOS 18 / macOS 15; TestFlight app "Daisy Deploy"; offline sample mode with a badge on every screen; Mac DMG (notarized) at the fixed URL `…/releases/download/mac-latest/Daisy.dmg` used by W-14.
- **Infra** (황지환 · 임채준): Terraform plan file is `plan.tfplan`; AWS is ECS Fargate + ALB in public subnets without NAT; cloud order AWS → GCP; apply and destroy only after human approval (`TF_RUN_APPROVED`); low-cost defaults (3-day logs, no deletion protection); the personal AWS account only runs plan, apply happens on the team account.
- **Sample repos**: image tags are commit hashes even locally (no `latest`); in `sample-msa` the Cloud Run backend allows unauthenticated calls but only through `internal` ingress.

**Undecided `[미정]`:** `deploy.yaml` schema (flat vs `services:` map) and secret delivery, container registry (Docker Hub / GHCR; GHCR used for now), CI/CD tool scope (GitHub Actions for app images; Jenkins runner being prototyped in `infra/`), on-prem deploy method and its relation to Terraform (ADR-003), HTTPS exposure method (Cloudflare Tunnel proposed), LLM and the fixed exchange rate, Terraform state store, ADR-007 widening, automatic rollback on health-check failure (proposed by 하은현), demo account and auth scope, "왜 AI인가" sentence, cloud-specific features.

### 12-5. `deploy.yaml` schema `[미정 — 9/29 draft]`

The AI input, the reference Terraform module inputs, and what the UI shows all come from this file. Changing it is a team decision.

```yaml
name: sample-app
port: 3000              # port the app listens on inside the container
healthcheck: /health    # ALB target group · Cloud Run startup probe · Docker healthcheck
env:                    # plain environment variables
  - NODE_ENV
secrets:                # secrets (delivery method undecided)
  - DATABASE_PASSWORD
database: true          # AWS RDS · GCP Cloud SQL · on-prem DB container
```

### 12-6. Glossary

| Term | Meaning |
|---|---|
| 배포 명세 (`deploy.yaml`) | Common spec: port, healthcheck path, env vars, secrets, whether a DB is needed |
| 대상 환경 | Where the app is deployed (on-prem, AWS, GCP) |
| 기준 모듈 | Hand-written reference Terraform per environment. Example for the AI, and the fallback if N-02 fails |
| 검증된 스크립트 | Per-environment Terraform that passed validate, plan, and the risk check, with a recorded history |
| 이미지 태그 | Always the **commit hash**. Never `latest` |
| PoC ID | `N-01`–`N-10` (Notion PoC plan) |

### 12-7. Schedule (KST)

| When | Goal |
|---|---|
| D1 (9/29–30) | Demo skeleton N-01–N-04, `deploy.yaml` fixed, API skeleton |
| D2 (10/1) | N-05 validate/fix loop, N-06 AWS, web connected to the API |
| D3 (10/2) | N-07 parallel apply, N-08 reuse, full flow passes once, demo rehearsal |
| 10/3 10:00 | Submit GitHub link and design doc link |
| **10/3 24:00** | **System works end to end (this repo's goal)** |
| 10/4 | Final presentation: 5 minutes, design doc + live demo, no slides |

Team meetings: daily 21:00–22:00 KST until 10/2 (Slack huddle). Backend: daily 18:00–19:00.

### 12-8. Budget

The team has ₩300,000 of cloud credit in total. ALB, NAT Gateway, and RDS cost money just by existing. Tell your human to clean up resources after testing.

### 12-9. Where things live

- Design docs, ADRs, PoC plan, meeting notes: team Notion (https://app.notion.com/p/5218bee9ada483ecba4881553589f692). If you have Notion access, read it there; otherwise ask your human.
- API agreement record: Notion "Backend API Endpoint" › "프론트 ↔ 백엔드 계약 초안 v0.2". The server's OpenAPI wins when they differ.
- Branch, commit, PR rules: `CONTRIBUTING.md`.
- Per-area rules and decisions logs: `{area}/AGENTS.md`.

## 13. Maintaining these files

- Keep this file short. Put area details in the area `AGENTS.md`, and link to specs instead of copying them.
- When a `(가칭)` or `[미정]` item is decided, update it here in the same PR that records the decision.
- An area `AGENTS.md` may add rules for its own area but may not loosen §4.
