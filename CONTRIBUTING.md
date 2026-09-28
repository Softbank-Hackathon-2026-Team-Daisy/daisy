# CONTRIBUTING — 브랜치 · 커밋 · PR 규칙

> 상태: **초안 (9/29, 김도영)**. 4일짜리 해커톤이라 **최소 규칙**만 둬요.
> 원칙: **`main`은 언제든 데모할 수 있는 상태**로 유지해요.

## 1. 브랜치 전략 (GitHub Flow)

```
main  ─────●─────────●──────────●────▶  항상 동작하는 상태 (보호됨)
            \       /  \        /
             feature    feature
```

- 긴 수명의 `develop` 브랜치는 두지 않아요. 기간이 짧아서 병합 단계만 늘어나요
- 모든 작업은 `main`에서 브랜치를 따서 PR로 돌아와요
- 브랜치는 **하루 안에** 머지하는 크기로 쪼개요. 오래 살면 충돌이 커져요

### 브랜치 이름

```
{파트}/{타입}-{짧은-설명}
```

| 파트 | 타입 |
|---|---|
| `web`, `ios`, `server`, `infra`, `docs`, `ci` | `feat`, `fix`, `refactor`, `docs`, `chore`, `test` |

예시

```
web/feat-plan-approval
server/feat-terraform-generate
infra/feat-gcp-cloudrun-module
ci/feat-image-pipeline
docs/chore-adr-008
```

## 2. 커밋 메시지

[Conventional Commits](https://www.conventionalcommits.org/) 형식에 파트를 scope로 붙여요.

```
{타입}({파트}): {무엇을 했는지, 한국어 가능}
```

예시

```
feat(web): plan 승인 화면에 삭제 리소스 강조 표시
fix(server): 재시도 횟수가 환경별로 세어지지 않던 문제 수정
feat(infra): GCP Cloud Run 기준 모듈 추가
docs: ADR-008 컨테이너 레지스트리 결정 기록
```

- 관련 PoC가 있으면 본문에 적어요: `Refs: N-03`

## 3. Pull Request

| 규칙 | 내용 |
|---|---|
| 리뷰 | **1명 승인** 후 머지. 같은 파트 팀원 우선, 없으면 팀장 |
| 머지 방식 | **Squash merge** (커밋 기록을 PR 단위로 깔끔하게) |
| 크기 | 가능하면 **변경 300줄 이하**. 크면 나눠요 |
| 템플릿 | PR 템플릿을 채워요 (조직 공통 `.github` 레포에 있어서 모든 레포에 자동 적용) |
| 인터페이스 변경 | `deploy.yaml`, API 계약, 모듈 입력 변수를 바꾸면 **관련 파트 담당자를 리뷰어로 추가**하고 Slack에 공유 |
| 셀프 머지 | 평소에는 금지. **예선 당일(10/3~4)만** 리뷰어가 바쁘면 PR을 만든 뒤 셀프 머지 허용 |

## 4. GitHub 설정 (팀장이 설정)

`Settings → Branches → Branch protection rules → main`

- [x] Require a pull request before merging
  - [x] Require approvals: **1**
- [x] Require status checks to pass (CI를 붙인 뒤 켜요)
- [x] Do not allow force pushes
- [x] Do not allow deletions

`Settings → General → Pull Requests`

- [x] Allow squash merging (나머지 merge 방식은 꺼요)
- [x] Automatically delete head branches

## 5. 이슈

작업을 시작하기 전에 이슈를 만들고, PR 본문에 `Closes #번호`를 적어요. 이슈 템플릿은 세 가지예요.

| 템플릿 | 언제 |
|---|---|
| 작업 | 구현할 기능, PoC (완료 기준과 실패 시 대안을 함께) |
| 버그 | 예상과 다르게 동작할 때 (로그의 비밀값은 지우고) |
| 결정 필요 | 팀이 골라야 할 선택지. 결정되면 노션 ADR로 옮겨요 |

## 6. 비밀값

- `.env`, `*.tfvars`, `*.tfstate`, 클라우드 키 파일은 **절대 커밋하지 않아요**
- 공유가 필요하면 GitHub Actions Secrets 또는 팀 비밀값 저장소 `[미정]`을 써요
- 실수로 커밋했다면 **즉시 키를 폐기·재발급**하고 팀에 알려요. 커밋을 지워도 기록에 남아요
