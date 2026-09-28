# CLAUDE.md — Team Daisy 공통 맥락

> 모든 파트의 AI 에이전트가 먼저 읽는 파일이에요. **모든 파트가 공유하는 사실만** 여기에 둬요.
> 파트별 규칙은 각 폴더의 `CLAUDE.md`(`web/`, `ios/`, `server/`, `infra/`)에 있어요.
> 상태: **초안 (9/29, 김도영)** — `[미정]` 표시는 회의에서 확정되면 고쳐요.

## 1. 프로젝트

**AI 기반 온프레미스·퍼블릭 클라우드 원터치 배포 시스템** (SoftBank Hackathon 2026 in Korea 예선, Team Daisy)

배포 환경만 선택하면 AI가 환경별 인프라 코드(Terraform)를 생성·검증해서, 같은 애플리케이션을 온프레미스와 퍼블릭 클라우드에 동시에 배포해요.

- 핵심 키워드: **이식성** — 같은 앱을 같은 상태로 여러 환경에
- "하이퍼스케일러" 대신 **"퍼블릭 클라우드"**라고 표현해요 (소규모 클라우드 사업자까지 확장 가능)

## 2. 배포 흐름 (7단계)

1. **앱 연결 (최초 1회)** — 사용자 저장소에 `Dockerfile` + `deploy.yaml`
2. **코드 반영** — PR → `main` merge
3. **이미지 생성** — GitHub Actions가 빌드·테스트 → **커밋 해시 태그** → 레지스트리 푸시 → 배포 서비스에 이벤트 전달
4. **환경 선택** — 웹 화면에서 온프레미스·AWS·GCP 다중 선택
5. **Terraform 생성 (AI)** — 환경마다 생성. 검증된 스크립트가 있으면 **이미지 태그만 교체해 재사용 (AI 호출 0회)**
6. **자동 검증·수정** — `validate` → `plan` → 위험 설정 검사. 실패하면 AI가 로그를 보고 수정, **최대 3회**. 넘으면 중단하고 화면에 알림
7. **승인·실행** — 사람이 plan을 보고 승인 → 환경별 **병렬 `apply`**, state는 환경별로 분리 보관

AI는 **판단이 필요한 곳(5·6단계)에만** 쓰고, 실행은 검증된 코드와 Terraform이 맡아요. 인프라 변경은 **반드시 사람 승인**을 거쳐요.

## 3. 레포 구조와 담당

```
daisy/                     ← 우리 배포 시스템 (이 레포)
├─ web/                    React + Vite SPA — 김도영, 박승준
├─ ios/                    Swift 앱 (승인·진행 상태·알림) — 박승준
├─ server/                 배포 서비스 API · AI · 검증 — 하은현, 김승환
├─ infra/
│  ├─ modules/onprem/      온프레미스 기준 Terraform 모듈 (Docker) — 황지환
│  ├─ modules/gcp/         GCP 기준 모듈 (Cloud Run 등) — 임채준
│  └─ modules/aws/         AWS 기준 모듈 (ECS·ALB·RDS) — 임채준
├─ docs/                   아키텍처 그림, ADR 사본
├─ .github/workflows/      우리 시스템용 CI (이슈·PR 템플릿은 조직 공통 `.github` 레포)
├─ CLAUDE.md               (이 파일)
└─ CONTRIBUTING.md         브랜치·커밋·PR 규칙
```

**배포 대상 샘플 앱은 별도 레포**예요. "사용자의 앱 저장소"를 흉내 내는 것이라 이 레포와 섞지 않아요.

| 레포 | 내용 | 담당 |
|---|---|---|
| `sample-monolith` | 모놀리스 샘플 + N-01 GitHub Actions 파이프라인 | 하은현(앱), 김도영(Actions) `[미정]` |
| `sample-msa` | 서비스 2개짜리 MSA 샘플 | 황지환 `[미정]` |
| `.github` | 조직 공통 이슈·PR 템플릿, 조직 소개 README | 김도영 |

## 4. 결정된 사항 (ADR 요약)

| ADR | 결정 |
|---|---|
| 001 | 역할: 웹(FE·BE) / 인프라(온프레미스·클라우드) |
| 002 | 주제: AI 기반 온프레미스·퍼블릭 클라우드 원터치 배포 시스템 |
| 003 | IaC는 **Terraform** |
| 004 | 앱 입력은 GitHub 저장소 + `main` merge + GitHub Actions |
| 005 | 온프레미스 런타임은 **Docker** |
| 006 | 프론트는 **React + Vite SPA** (Next.js 아님). 최소 스택으로 시작하고 막힐 때만 추가 |
| 007 | 웹은 전체 흐름, Swift 앱은 승인·진행 상태·푸시 알림만 |

미정: 백엔드 언어, LLM, 컨테이너 레지스트리, state 저장소, 온프레미스 연결 방식(에이전트 Pull / SSH / Docker provider), 외부 공개 방식(Cloudflare Tunnel / ngrok), API 계약 방식 `[미정]`

## 5. `deploy.yaml` 스키마 `[미정 — 9/29 회의 초안]`

AI의 입력, 기준 Terraform 모듈의 입력, 화면에 보여줄 정보가 **모두 이 파일에서 나와요.** 바꿀 때는 전 파트에 공유해요.

```yaml
name: sample-app
port: 3000              # 컨테이너 안에서 앱이 요청을 받는 포트
healthcheck: /health    # ALB 대상 그룹 · Cloud Run 시작 프로브 · Docker 헬스체크
env:                    # 일반 환경변수
  - NODE_ENV
secrets:                # 비밀값 (전달 방식 미정)
  - DATABASE_PASSWORD
database: true          # AWS RDS · GCP Cloud SQL · 온프레미스 DB 컨테이너
```

## 6. 용어

| 용어 | 뜻 |
|---|---|
| 배포 명세 (`deploy.yaml`) | 포트, 헬스체크 경로, 환경변수, 비밀값, DB 여부를 적은 공통 명세 |
| 대상 환경 | 앱이 배포될 곳 (온프레미스, AWS, GCP) |
| 기준 모듈 | 사람이 직접 만든 환경별 정답 Terraform. AI 생성의 참고 예시이자 N-02 실패 시 대안 |
| 검증된 스크립트 | validate·plan·위험 설정 검사를 통과해 이력이 남은 환경별 Terraform |
| 이미지 태그 | 항상 **커밋 해시**. `latest`는 쓰지 않아요 |
| PoC ID | `N-01`~`N-10` (노션 PoC 계획) |

## 7. 모든 파트 공통 규칙

- **비밀값을 커밋하지 않아요.** `.env`, `*.tfvars`, 클라우드 키 파일, `*.tfstate`는 커밋 금지 (`.gitignore`에 포함)
- **`main`에 직접 push하지 않아요.** 반드시 PR (자세한 건 `CONTRIBUTING.md`)
- **다른 파트 폴더는 수정하기 전에 담당자에게 먼저 물어봐요.** 인터페이스(`deploy.yaml`, API 계약, 모듈 입력 변수)를 바꾸면 Slack에 공유해요
- **목업은 목업이라고 표시해요.** 코드에 `// MOCK:` 주석, 화면에는 목업 배지. 발표 규칙상 목업을 숨기면 안 돼요
- **결정을 내리면 기록해요.** 선택지와 이유를 노션 ADR에 한 줄이라도. 심사에서 "대안·논의 과정"을 봐요
- **막혔다 풀리면 기록해요.** 개인 메모 페이지의 Trouble Shooting에 "증상, 원인, 해결"
- **클라우드 리소스는 쓰고 나면 정리해요.** 지원금은 팀당 ₩300,000. ALB·NAT Gateway·RDS는 켜두기만 해도 과금

## 8. AI 에이전트 작업 규칙

- 작업 전에 이 파일과 **해당 폴더의 `CLAUDE.md`**를 먼저 읽어요
- 요청받은 폴더 밖의 파일은 바꾸지 않아요. 필요하면 변경 제안만 남겨요
- `deploy.yaml` 스키마, API 계약, Terraform 모듈 입력 변수처럼 **파트 사이의 약속**은 임의로 바꾸지 않아요
- 인프라를 실제로 만들거나 지우는 명령(`terraform apply`, `terraform destroy`, 클라우드 CLI 삭제 명령)은 **사람 확인 없이 실행하지 않아요**
- 커밋 메시지와 PR은 `CONTRIBUTING.md` 형식을 따라요

## 9. 일정

| 날짜 | 목표 |
|---|---|
| D1 (9/29~30) | 데모 뼈대 N-01·N-02·N-03·N-04, `deploy.yaml` 확정, API 뼈대 |
| D2 (10/1) | N-05 검증 루프, N-06 AWS, 웹 화면과 API 연결 |
| D3 (10/2) | N-07 병렬 apply, N-08 재사용, 전체 흐름 1회 통과, 데모 리허설 |
| 10/3 10:00 | 제출: GitHub 링크, 설계 문서 링크 |
| 10/3~4 | 예선 (10/3 중간보고, 10/4 최종 발표 5분: 설계 문서 + 라이브 데모, 슬라이드 금지) |

## 10. 참고 링크 (Notion)

- 팀 홈: SoftBank Hackathon 2026 (Team Daisy)
- What is <서비스명> · 플로우차트 설계서 · PoC 계획 · 설계 결정 기록 (ADR) · Members' Roles / Task defi
