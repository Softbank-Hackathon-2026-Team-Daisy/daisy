# AGENTS.md — infra/ (환경별 기준 Terraform 모듈 · 러너 · state)

담당: 황지환 (`jihwan77`, 온프레미스), 임채준 (`dlacowns21`, 클라우드 GCP · AWS, state 백엔드). 상태: v1 (2026-09-30).

루트 `AGENTS.md`를 먼저 따라요. 이 파일은 `infra/`에만 해당하는 규칙을 더하고, 루트 하드 규칙(§4)을 느슨하게 하지 않아요.
두 담당자가 같이 쓰는 파일이에요. **양쪽에 영향을 주는 규칙은 두 담당자가 합의해야 확정**이고, 한쪽이 제안한 것은 `(가칭)`으로 둬요.
무엇을 만드는지는 `SPEC.md`에 있어요. 클라우드는 [`SPEC.md`](./SPEC.md)(임채준), 온프레미스 명세는 황지환이 추가해요. **여기서 작업하기 전에 해당 `SPEC.md`를 읽어요.**

## 1. 이 폴더가 하는 일

| 누가 | 무엇 | PoC |
|---|---|---|
| 황지환 | 온프레미스 기준 모듈 (Docker), 터널 외부 공개 | N-04 |
| 임채준 | GCP 기준 모듈 (Cloud Run) | N-03 |
| 임채준 | AWS 기준 모듈 (ECS Fargate · ALB · RDS) | N-06 |
| 임채준 | state 백엔드 (환경별 분리 · 잠금), Jenkins 러너 프로토타입 | N-07 |

**기준 모듈** = 사람이 직접 만든 환경별 정답 Terraform이에요. AI 생성의 참고 템플릿이자 N-02가 실패했을 때의 대안이에요.

## 2. 기술 스택

| 항목 | 값 | 이유 |
|---|---|---|
| IaC | **Terraform** | ADR-003 |
| Terraform 버전 | **1.16.4** `(가칭)` | 러너 · AI 작성 규칙 · 모듈이 같은 버전을 써요. 모듈은 `required_version = ">= 1.11"` (S3 네이티브 잠금) |
| provider | AWS `hashicorp/aws ~> 6.0`, Google `hashicorp/google ~> 8.0`, 온프레미스: (황지환) | |
| 온프레미스 런타임 | **Docker** | ADR-005 |
| 러너 | Ubuntu 24.04 + Jenkins LTS `(가칭)` | CI/CD 도구는 루트 `[미정]`. 임채준이 VM 프로토타입으로 검증 중이에요 (클라우드 `SPEC.md` §12) |

## 3. 폴더 구조와 경계

```
infra/
├─ AGENTS.md          이 파일 (공통 규칙 · 결정 기록)
├─ SPEC.md            클라우드 명세 (임채준). 온프레미스 명세는 황지환이 추가
├─ modules/
│  ├─ onprem/         ← 황지환
│  ├─ aws/            ← 임채준
│  └─ gcp/            ← 임채준
├─ bootstrap/ (가칭)  state 버킷 · 클라우드 계정 1회 준비 ← 임채준
├─ jenkins/   (가칭)  러너 설치 · CI/CD 파이프라인 ← 임채준 (프로토타입)
└─ scripts/   (가칭)  tf-run.sh 등 러너 보조 ← 임채준
```

- **다른 담당자의 모듈 폴더는 고치지 않아요.** 필요하면 이슈로 요청해요 (루트 §9)
- `jenkins/`·`scripts/`가 온프레미스 배포까지 부르게 되면, 그 부분은 황지환과 같이 정해요

## 4. 모든 기준 모듈의 공통 규약 `(가칭 — 황지환 확인 필요)`

server AI(김승환)와 러너가 환경에 상관없이 같은 방식으로 모듈을 다루게 해요. 클라우드 쪽 자세한 정의는 `SPEC.md` §3에 있어요.

| 항목 | 규약 |
|---|---|
| 파일 | `main.tf` · `variables.tf` · `outputs.tf` 3개짜리 **루트 모듈** (AI 생성본과 같은 모양) |
| backend | 모듈에 쓰지 않아요. 러너가 `backend.tf` + `-backend-config`로 주입해요 |
| 입력 변수 | `deploy.yaml` 키와 1:1: `name`, `port`, `healthcheck`, `env`, `secrets`, `database`. 여기에 `image`(태그 없는 주소), `image_tag`(필수, 커밋 해시)를 더해요 |
| 출력 | `service_url` (스킴 포함, 끝에 `/` 없음). 헬스체크 주소 = `service_url` + `healthcheck` |
| state key | `{app}/{env}/terraform.tfstate`, `env`는 `onprem` · `aws` · `gcp`. 저장소는 루트 `[미정]` |
| DB 접속 환경변수 | `DB_HOST` · `DB_PORT` · `DB_NAME` · `DB_USER` · `DB_PASSWORD`. 세 환경이 같은 이름을 넣어야 이식성이 지켜져요 |
| 자격증명 | 코드 · 변수 어디에도 없어요. 러너의 환경변수로만 받아요 |
| 태그 · 라벨 | `Project=daisy`, `App={name}`, `ManagedBy=terraform`. 정리할 때 이걸로 남은 리소스를 찾아요 |

## 5. 컨벤션

- 커밋 · 브랜치 · PR은 `CONTRIBUTING.md`를 따라요
- `terraform fmt`를 통과한 코드만 커밋해요
- `.terraform.lock.hcl`은 커밋해요. 러너와 개발 기기가 달라서 `linux_amd64` · `linux_arm64` · `darwin_arm64` 해시를 모두 넣어요
- `*.tfvars`, `*.tfstate`, plan 파일, 키 파일은 커밋하지 않아요. 예시는 `*.tfvars.example`에 비밀값 없이 둬요
- plan 파일 이름은 `plan.tfplan`이에요. 루트 `.gitignore`가 `*.tfplan`만 막아요
- state와 plan이 생기는 작업 디렉터리는 레포 밖에 둬요
- 리소스 이름은 `daisy-{name}` 접두사를 붙여요
- 검증 순서는 `fmt` → `validate` → `plan`이에요. PR에는 실제 출력을 붙이고, 계정 ID · 프로젝트 ID는 가려요

## 6. 다른 파트와의 약속

- 모듈 입력 변수와 출력은 **infra가 제공하는 계약**이에요 (루트 §5-2). 바꾸면 김승환 · 하은현에게 먼저 알려요
- `deploy.yaml` 스키마는 팀 결정이라 회의 후에 반영해요
- 리전: AWS `ap-northeast-2`, GCP `asia-northeast3` `[미정]`
- terraform을 실행하는 쪽(Jenkins 또는 server)은 클라우드 `SPEC.md` §3-4의 러너 규약 순서를 따라요

## 7. 실행 방법

```bash
# 모듈 검증 (자격증명 필요 없음)
cd infra/modules/<env>
terraform fmt -check && terraform init -backend=false && terraform validate

# plan · apply는 러너로 해요. 작업 디렉터리는 레포 밖이에요 (클라우드 SPEC.md §3-4)
APP=hellocalc IMAGE_TAG=<커밋 해시 40자> infra/scripts/tf-run.sh aws plan
```

온프레미스 실행 방법: (황지환)

## 8. AI 에이전트에게

- 이 폴더 밖은 건드리지 않아요. 필요하면 이슈로 요청해요 (루트 §9)
- 작업을 요청한 담당자의 모듈 폴더만 고쳐요
- `terraform apply` · `destroy`, 클라우드 CLI와 Docker 호스트의 생성 · 삭제 명령은 **사람 확인 없이 실행하지 않아요** (루트 §4-2). `fmt` · `validate` · `plan`은 괜찮아요
- `TF_RUN_APPROVED`를 직접 설정하지 않아요. 사람이 Jenkins에서 승인한 뒤에만 쓰는 값이에요
- §4 공통 규약은 임의로 바꾸지 않아요
- 목업에는 `# MOCK:` 주석을 달아요 (Groovy·JS는 `// MOCK:`)
- 작업 전에 아래 결정 기록을 읽어요

## 9. 결정 기록

`[클라우드]` · `[온프레미스]`는 그 담당자 혼자 정한 1단계 결정이에요. 표시가 없는 줄은 infra 공통이에요.

| 날짜 | 결정 | 이유 | 단계 |
|---|---|---|---|
| 2026-09-30 | 파트 규칙 파일을 `infra/AGENTS.md`로 바꿈 (#4) | 루트 #2에서 `AGENTS.md`로 통일하기로 함 | 1 |
| 2026-09-30 | 기준 모듈은 3파일 루트 모듈 `(가칭 · 황지환 확인)` | AI 생성 형식과 같아서 템플릿 · 폴백 · 재사용을 한 벌로 해요 | 2 |
| 2026-09-30 | 모듈에 `backend` 블록 없음, 러너가 주입 `(가칭 · 황지환 확인)` | state 저장소 미정에 막히지 않고, AI 작성 규칙과도 같아요 | 2 |
| 2026-09-30 | 모듈 변수 이름 = `deploy.yaml` 키, 출력은 `service_url` `(가칭 · 황지환 확인)` | 기존 약속("deploy.yaml과 1:1")을 구체화했어요. 소비자는 AI · 러너 | 2 |
| 2026-09-30 | terraform 1.16.4 고정 `(가칭 · 황지환 확인)` | 러너 · AI 작성 규칙 · 서버가 같은 버전을 써요 | 2 |
| 2026-09-30 | plan 파일 이름은 `plan.tfplan` | `.gitignore`가 `*.tfplan`만 막아요 | 2 |
| 2026-09-30 | `[클라우드]` AWS는 ECS Fargate + ALB. 태스크는 public 서브넷 + 공인 IP, NAT 없음 | NAT는 켜두기만 해도 하루 약 ₩2천. 인바운드는 ALB SG만 허용해서 노출이 없어요 | 1 |
| 2026-09-30 | `[클라우드]` 로그 보존 3일, 삭제 보호 끔, Secrets Manager 복구 기간 0일 | 해커톤 중 destroy · 재생성을 반복해요 | 1 |
| 2026-09-30 | `[클라우드]` 구현 순서 AWS → GCP | 담당자 결정. 팀 일정(N-03이 D1)과 달라서 공유 필요 (클라우드 SPEC D-10) | 1 |
| 2026-09-30 | `[클라우드]` 팀원 서버 연결 전에는 Mac VM(`daisy-runner`, Ubuntu 24.04 arm64)에서 Jenkins CI · CD를 돌려요 | 서버에 연결할 수 없어요. 설치 스크립트와 Jenkinsfile을 레포에 둬서 그대로 옮겨요 | 1 |
| 2026-09-30 | `[클라우드]` VM 단계는 개인 AWS · GCP 계정과 개인 Docker Hub 공개 저장소를 써요 | 팀 계정 · 레지스트리 미정. GHCR 패키지가 비공개예요 | 1 |
| 2026-09-30 | `[클라우드]` 개인 AWS 계정에서는 plan까지만 해요. IAM은 `ReadOnlyAccess`, Jenkins `PLAN_ONLY=1`, Zero spend budget. apply는 팀 계정에서 | 개인 계정은 프리티어가 끝나서 ALB · Fargate가 유료예요. 개인 비용 0원이 조건이에요 | 1 |
| 2026-09-30 | `[클라우드]` CI는 `linux/amd64,linux/arm64`로 푸시해요 | Cloud Run은 amd64만 실행하고, 러너는 arm64예요 | 1 |
| 2026-09-30 | `[클라우드]` apply · destroy는 터미널 입력이나 Jenkins `input` 승인 뒤 `TF_RUN_APPROVED`로만 실행해요 | 인프라 변경은 반드시 사람 승인 (루트 §4-2) | 1 |

## 10. 아직 정하지 못한 것

| 무엇 | 상태 | 누가 |
|---|---|---|
| §4 공통 규약 | 임채준 제안. 온프레미스에도 맞는지 확인 필요 | 황지환 |
| state 저장소 | S3 버킷 하나에 `{app}/{env}` key로 나누자는 제안. 온프레미스 state도 같이 둘지 | 팀 회의 · 황지환 |
| CI/CD 도구 · terraform 실행 주체 | Jenkins로 전달받았지만, server는 Spring이 직접 실행하기로 기록해 둠 | **팀 회의** |
| 컨테이너 레지스트리 | 루트 `[미정]` | **팀 회의** |
| 온프레미스 배포 방식과 Terraform의 관계 | 루트 `[미정]` | 황지환 · 팀 회의 |
| Jenkins 호스트 | 팀원 서버가 러너이자 온프레미스 대상. 자격증명과 배포 대상이 한 기기에 모여요 | **팀 회의** |
