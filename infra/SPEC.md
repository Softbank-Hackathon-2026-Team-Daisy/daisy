# SPEC.md — infra/ 온프레미스 · 클라우드 기준 모듈과 state 백엔드

> 작성: 임채준 (`dlacowns21`, 클라우드), 황지환 (`jihwan77`, 온프레미스) · 상태: **초안 (온프레미스 추가: 10/1)**
> 참조: 루트 `CLAUDE.md`(main) · 루트 `AGENTS.md` v1(`docs/chore-agents-md` 브랜치, 머지 대기) · `infra/AGENTS.md`(#10, 인프라 공통 규칙 · 결정 기록) · `server/AGENTS.md` · `sample-monolith`
> 기존 §1~§13은 클라우드 설계·러너 프로토타입을 다뤄요. 온프레미스 명세는 **§16**에 추가했어요. 10/1 전달된 Jenkins 실행·승인 합의와 기존 프로토타입 설명의 차이는 §16-6·§16-10에 구분했어요.
> 표시: `(가칭)` = 제안(남의 영역이거나 팀 결정 전), `[미정]` = 팀 결정 대기, 표시 없음 = 내 영역에서 확정.

---

## 0. 요약

| 만드는 것 | PoC | 우선순위 |
|---|---|---|
| **온프레미스 기준 모듈** — 사전 생성 VM의 Docker 컨테이너를 Terraform으로 관리 (§16) | N-04 | M |
| **state 백엔드** — 환경별 state 분리·잠금 | N-07 | M |
| **AWS 기준 모듈** — ECS Fargate + ALB (+ RDS) | N-06 | M (RDS는 S) |
| **GCP 기준 모듈** — Cloud Run (+ Cloud SQL) | N-03 | M (Cloud SQL은 S) |

- 순서: state 백엔드 → **AWS → GCP** (담당자 결정).
- 팀원 서버(Jenkins 러너 + 온프레미스 대상)에 연결되기 전까지는 **Mac의 VM `daisy-runner`에서 Jenkins CI·CD를 돌리고, 개인 AWS·GCP 계정**으로 검증해요 (§12). 옮길 때는 §13을 따라요.
- **핵심 원칙: 모듈은 "누가 실행하는지, state가 어디 있는지, 어느 레지스트리인지" 몰라도 돌아가요.** 전부 변수와 러너 주입으로 받아요. 그래서 팀 미정 항목(CI/CD 도구, 레지스트리, state 저장소)에 구현이 막히지 않아요.

M = 예선 데모 필수, S = 여유 있을 때

---

## 1. 경계: 배포 과정에서 infra 클라우드가 맡는 곳

붙여 준 배포 과정(Jenkins + Terraform + Claude API)을 단계별로 나누면 이래요. **내 영역은 굵게** 표시했어요.

| 단계 | 담당 | infra 클라우드가 주는 것 |
|---|---|---|
| CI: 빌드 · 이미지 푸시 | CI (김도영). 지금은 GitHub Actions(N-01), Jenkins 전환은 D-1 | **Jenkins CI 프로토타입** (§12). 이미지는 모든 환경에서 pull할 수 있어야 해요 (D-3) |
| 환경 선택 · 파이프라인 시작 | web · server | 없음 |
| 인프라 코드 확인 · AI 생성 | server AI (김승환) | **참고 템플릿 = 기준 모듈**, 작성 규칙·비용 제약 값 (§4) |
| validate · plan · 보안 검사 · AI 재시도 | server AI (김승환) | **보안 검사 규칙 목록** (§4-3). 기준 모듈은 이 규칙을 통과해요 |
| 인프라 코드 저장 (인프라 저장소) | `[미정]` (D-8) | 폴더 구조가 기준 모듈과 같게 (§2-1) |
| plan 승인 | web · ios · server | 없음 |
| terraform apply (환경별 병렬) | 실행 주체 `[미정]` — Jenkins 또는 server (D-2) | **러너 규약** (§3-4), 참고 구현 `tf-run.sh`, **Jenkins CD 프로토타입** (§12) |
| **state 원격 저장 · 환경별 분리** | **infra 클라우드 (나)** | **S3 버킷, 키 규칙, 잠금** (§7) |
| 배포 확인 (헬스체크) | 실행 주체 | **`service_url` 출력** (§3-2) |
| Jenkins 러너 · Credentials | 팀원 서버 (D-9). 연결 전에는 infra 클라우드가 VM으로 대신해요 (§12) | **설치 스크립트, 필요한 자격증명과 권한 목록** (§3-5, §12) |

범위 밖 (이번에 안 해요): 커스텀 도메인·HTTPS(S), 비공개 레지스트리 인증(S), 기존 VPC 재사용, MSA 여러 서비스를 한 ALB에 묶기(스키마 결정 후), 오토스케일링, WAF, Multi-AZ, 롤백 기능(server).

---

## 2. 설계 원칙

### 2-1. 기준 모듈 = AI 생성본과 같은 모양

기준 모듈은 `main.tf` · `variables.tf` · `outputs.tf` **3파일짜리 루트 모듈**이에요. AI 작성 규칙과 똑같은 모양이라 한 벌로 세 가지를 해요.

1. **AI 참고 템플릿**: 시스템 프롬프트에 그대로 넣어요
2. **N-02 실패 시 대안**: 디렉터리를 복사하면 바로 검증된 스크립트가 돼요
3. **재사용 배포**: `image_tag` 변수만 바꿔요 (AI 호출 0회)

### 2-2. 나머지 원칙

- **`backend` 블록을 쓰지 않아요.** state 위치는 러너가 주입해요 (§3-4). state 저장소가 바뀌어도 모듈은 그대로예요
- **이미지 주소·태그·비밀값은 전부 변수.** 레지스트리가 바뀌면 변수 값만 바뀌어요
- **자격증명은 코드·변수 어디에도 없어요.** 러너의 환경변수(`AWS_*`, `GOOGLE_APPLICATION_CREDENTIALS`)로만 받아요
- **최소 비용이 기본값.** NAT Gateway·Multi-AZ 없음, 로그 보존 3일, 모든 리소스에 태그·라벨을 달아서 정리해요
- **가장 작은 것부터.** 샘플 앱 HelloCalc는 `database: false`라서 DB 없는 경로가 M이에요

---

## 3. 공통 계약 (모든 클라우드 모듈)

모듈 입력 변수는 infra가 제공하는 계약이에요 (루트 §5-2, 소비자: server AI 김승환). 바꾸면 소비자에게 먼저 알려요. **온프레미스 모듈(황지환)과 같은 이름을 쓰도록 맞춰요** (D-7).

### 3-1. 입력 변수

이름은 `infra/AGENTS.md` §4 공통 규약대로 **`deploy.yaml` 키와 1:1**이에요.

| 변수 | 타입 · 기본값 | 출처 | 비고 |
|---|---|---|---|
| `name` | string, 필수 | `deploy.yaml` `name` | `^[a-z][a-z0-9-]{1,19}$`. ALB 이름 32자, GCP SA 30자 제한 때문에 20자 이하 |
| `image` | string, 필수 | 레지스트리 설정 | **태그 없는** 저장소 주소. Docker Hub는 `docker.io/` 접두사까지 |
| `image_tag` | string, 필수 | 매 배포 (커밋 해시) | `^[0-9a-f]{7,40}$` 검증으로 `latest` 거부 |
| `port` | number, 필수 | `deploy.yaml` `port` | |
| `healthcheck` | string, 기본 `/health` | `deploy.yaml` `healthcheck` | `/`로 시작 |
| `env` | map(string), 기본 `{}` | `deploy.yaml` `env`(이름) + 값(출처 `[미정]`) | `PORT`는 넣지 않아요 (Cloud Run 예약어) |
| `secrets` | map(string), `sensitive`, 기본 `{}` | `deploy.yaml` `secrets`(이름) + 값은 실행 시 Credentials | 파일에 쓰지 않고 `TF_VAR_secrets` 환경변수로만 |
| `database` | bool, 기본 `false` | `deploy.yaml` `database` | `true` 경로는 S |
| `cpu` | number (vCPU), 기본 `0.25` | `(가칭)` `deploy.yaml` 확장 (D-5) | Cloud Run은 1 미만이면 1로 올려요 |
| `memory` | number (MiB), 기본 `512` | `(가칭)` (D-5) | Fargate 허용 조합만 (§5-3) |
| `instances` | number, 기본 `1`, 최대 `2` | `(가칭)` (D-5) | ECS `desired_count` / Cloud Run 최대 인스턴스 |
| `region` | string | 대상 환경 등록 | 기본 AWS `ap-northeast-2`, GCP `asia-northeast3` (D-11) |
| `project_id` | string, **GCP만** 필수 | 대상 환경 등록 | |

### 3-2. 출력

| 출력 | 값 | 규칙 |
|---|---|---|
| `service_url` | AWS `http://<ALB DNS>` · GCP Cloud Run `uri` | 스킴 포함, 끝에 `/` 없음. 헬스체크 주소 = `service_url` + `healthcheck` |

`service_url`은 server `deployment_target.public_url`로 들어가요.

### 3-3. 이름 · 태그 규칙

- 리소스 이름: `daisy-{name}` 접두사 (예: `daisy-hellocalc-alb`, `daisy-hellocalc-tg`)
- AWS: provider `default_tags`로 `Project=daisy`, `App={name}`, `ManagedBy=terraform`
- GCP: 모든 리소스에 `labels = { project = "daisy", app = name, managed-by = "terraform" }`
- 정리할 때 이 태그·라벨로 남은 리소스가 0인지 확인해요

### 3-4. 러너 규약 — Jenkins든 server든 같은 순서

실행 주체가 정해지지 않았어도(D-2) 아래 순서만 지키면 돼요. Jenkinsfile의 `sh` 단계에 그대로 옮길 수 있게 썼어요.

```bash
# 0) 작업 디렉터리 = 검증된 스크립트 (기준 모듈 복사본 또는 AI 생성본)
#    러너는 backend.tf 한 파일만 더해요 (생성 코드에는 backend 블록 금지)
#    backend는 환경마다 그 환경의 저장소예요 (§7): aws → "s3", gcp → "gcs"
printf 'terraform {\n  backend "s3" {}\n}\n' > backend.tf     # aws 예시

# 1) 자격증명은 환경변수로만 주입 (Jenkins withCredentials 등)
#    AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY  ← AWS 배포 + AWS state 버킷
#    GOOGLE_APPLICATION_CREDENTIALS             ← GCP 배포 + GCP state 버킷
#    TF_VAR_secrets='{"DATABASE_PASSWORD":"..."}' ← 앱 비밀값

# 2) state 경로 주입. 환경마다 저장소와 key가 달라서 병렬 apply가 서로 막히지 않아요
#    aws: S3 (잠금은 use_lockfile)
terraform init -input=false \
  -backend-config="bucket=${TF_STATE_BUCKET}" \
  -backend-config="key=${APP}/${ENV}/terraform.tfstate" \
  -backend-config="region=ap-northeast-2" \
  -backend-config="encrypt=true" \
  -backend-config="use_lockfile=true"
#    gcp: GCS (잠금은 자동)
#    terraform init -input=false -backend-config="bucket=<GCP state 버킷>" -backend-config="prefix=${APP}/${ENV}"

# 3) 검증
terraform validate -no-color
terraform plan -input=false -no-color -out=plan.tfplan \
  -var-file=app.tfvars.json -var="image_tag=${IMAGE_TAG}"
terraform show -json plan.tfplan > plan.json   # 위험 검사 입력. 비밀값이 들어 있어서 로그에 남기지 않아요

# 4) 사람 승인 후
terraform apply -input=false -no-color plan.tfplan
terraform output -raw service_url
```

참고 구현: [`infra/scripts/tf-run.sh`](scripts/tf-run.sh). 위 순서를 그대로 실행하고 작업 디렉터리를 레포 밖(`$WORK_ROOT/$APP/$ENV/`)에 둬요. **plan(3)과 apply(4)는 다른 실행이에요.** plan마다 `plans/<PLAN_ID>/` 폴더를 따로 만들고, apply는 승인한 `PLAN_ID`의 plan만 적용해요 (§12-7). apply·destroy는 터미널에서 환경 이름을 입력하거나, 승인된 실행(`daisy-cd-apply`)에서 `TF_RUN_APPROVED=<env>`로만 실행돼요.

- `app.tfvars.json`: `deploy.yaml`과 대상 환경 정보에서 러너가 만드는 **비밀값 없는** 변수 파일
- `ENV`는 `onprem` · `aws` · `gcp` 중 하나
- key는 지금 `{app}/{env}`예요. 서버 ID 기준 `{project_id}/{target_id}`로 바꿀 예정이에요 `(가칭)` (§7-1)
- plan 파일 이름은 `plan.tfplan`이에요. 루트 `.gitignore`가 `*.tfplan`만 막아서 확장자가 없는 `tfplan`은 실수로 커밋될 수 있어요
- plan 파일과 state에는 비밀값이 들어가요. 작업 디렉터리는 레포 밖에 두고 끝나면 지워요 (server `AGENTS.md` §10과 같은 규칙)

### 3-5. 자격증명 (Jenkins Credentials에 넣을 것, 클라우드 부분)

| ID `(가칭)` | 종류 | 내용 | 권한 |
|---|---|---|---|
| `aws-deployer` | Username/Password (액세스 키 ID / 시크릿) | 전용 IAM 사용자 `daisy-deployer` | ECS · ELBv2 · EC2(VPC·SG) · IAM(`daisy-*` 역할 생성·PassRole) · CloudWatch Logs · Secrets Manager · RDS(S) · **AWS** state 버킷(`ListBucket`, `GetObject`, `PutObject`, 잠금 파일 `*.tflock`의 `DeleteObject`) |
| `gcp-deployer` | Secret file (JSON) | SA `daisy-deployer@<project>` 키 | `run.admin`, `iam.serviceAccountAdmin`, `iam.serviceAccountUser`, `secretmanager.admin`, **GCP** state 버킷의 `storage.objectAdmin`(버킷 단위) (+ 비공개 이미지면 `artifactregistry.admin`, DB면 `cloudsql.admin`) |
| `registry` | Username/Password | 레지스트리 계정 + 쓰기 토큰 (CI 푸시용) | 이미지 저장소 쓰기 |

- 개인 관리자 키를 공유하지 않아요. 전용 사용자·SA를 만들어요
- 권한 목록은 모듈 apply가 한 번 성공한 뒤 실제로 필요한 것만 남겨 확정해요 (S)
- VM 단계(개인 계정)에서는 샌드박스라서 관리자 권한으로 시작해요. 팀 계정으로 옮길 때 위 권한으로 줄여요 (§13)

---

## 4. server AI(김승환)에게 주는 값 — 시스템 프롬프트 고정 항목

붙여 준 설계의 "작성 규칙 · 보안 정책 · 비용 제약 · 참고 템플릿"은 infra가 값을 정하고 김승환이 프롬프트에 넣어요. **기준 모듈이 이 규칙을 모두 지키는 정답 예시**예요.

### 4-1. 작성 규칙

| 항목 | 값 |
|---|---|
| Terraform | `required_version = ">= 1.11"` (S3 네이티브 잠금 `use_lockfile` 정식 지원). 러너와 같은 **1.16.4**로 고정 (`infra/AGENTS.md` §2) |
| provider | AWS `hashicorp/aws ~> 6.0`, GCP `hashicorp/google ~> 8.0`. `.terraform.lock.hcl`은 커밋해요 |
| 파일 | `main.tf`(terraform·provider 블록 포함), `variables.tf`, `outputs.tf` 3개만 |
| 필수 변수 | `image_tag` (기본값 없음). 나머지는 §3-1 |
| 필수 출력 | `service_url` |
| 이름 | §3-3 |
| 금지 | `backend` 블록, 자격증명·비밀값 리터럴, `latest` 태그 |

### 4-2. 비용 제약

| 항목 | AWS | GCP |
|---|---|---|
| 컴퓨팅 최대 | Fargate 1 vCPU / 2048 MiB, 태스크 2개 | Cloud Run cpu 1 / 1 GiB, 인스턴스 0~2 |
| DB (S) | `db.t4g.micro`, 20 GiB gp3, Single-AZ | `db-f1-micro`, HA 없음 |
| 금지 | NAT Gateway, Multi-AZ DB, Container Insights, EIP | 최소 인스턴스 1 이상(상시 과금), VPC 커넥터 |
| 로그 | CloudWatch 보존 3일 | 기본값 |

- ALB는 **서로 다른 AZ의 서브넷 2개가 필수**예요. 이건 금지된 "Multi-AZ"(DB 이중화)와 달라요. 프롬프트에 같이 적어서 AI가 서브넷을 1개만 만들지 않게 해요
- 대략 비용 (서울 리전 온디맨드, 추정): AWS 기본 구성(ALB + Fargate 1개 + 공인 IPv4 3개) **하루 약 ₩2천**, RDS 포함 약 ₩3천. NAT Gateway를 쓰면 하루 약 ₩2천이 더 붙어요. Cloud Run은 요청이 없으면 거의 0

### 4-3. 보안 정책 → 위험 검사 규칙

위험 검사 구현은 김승환 영역이에요. 아래는 **기준 모듈이 통과하는 규칙 목록**이고, 검사기가 같은 목록을 쓰면 기준 모듈이 오탐 없이 통과해요.

| # | 규칙 | AWS | GCP |
|---|---|---|---|
| R-1 | 인터넷 인바운드(`0.0.0.0/0`, `::/0`)는 **공개 LB의 80·443만** | 보안 그룹 ingress | `allUsers` `run.invoker`는 공개 서비스에만 |
| R-2 | 앱은 LB에서만 받음 | 앱 SG ingress 출처 = ALB SG | — |
| R-3 | DB는 private, 외부 노출 없음 | `publicly_accessible = false`, private 서브넷, DB SG 출처 = 앱 SG | Cloud SQL 공인 IP 없음 |
| R-4 | 비밀값 하드코딩 금지 | 비밀값은 `sensitive` 변수 → Secrets Manager 참조 | Secret Manager 참조 |
| R-5 | 암호화 | RDS `storage_encrypted = true`, state 버킷 SSE | 기본 암호화 |
| R-6 | 최소 권한 | `Action = "*"`인 정책 없음, 실행 역할은 자기 비밀값만 읽기 | 전용 SA, `roles/owner`·`roles/editor` 금지 |

**허용 (오탐 처리하지 않을 것)**
- 앱의 아웃바운드 `0.0.0.0/0`: 외부 레지스트리에서 이미지를 pull하려면 필요해요
- AWS 관리형 정책 `AmazonECSTaskExecutionRolePolicy`: 내부에 `Resource = "*"`가 있지만 ECS 표준이에요
- RDS `skip_final_snapshot = true`, `deletion_protection = false`: 해커톤 중 정리를 위해서예요

---

## 5. AWS 기준 모듈 (N-06) — 먼저

### 5-0. 고정 네트워크와 앱 배포를 나눠요 (10/1)

**VPC · 서브넷은 한 번 만들어 두고, 앱 배포는 ALB · ECS · 보안 그룹만 만들고 지워요.** 처음에는 앱 모듈이 배포 때마다 VPC까지 만들고 destroy 때 같이 지웠는데, 불필요한 반복이라 바꿨어요.

| 층 | 위치 | 만드는 것 | 수명 |
|---|---|---|---|
| 고정 네트워크 | `infra/bootstrap/aws-network/` | VPC `10.20.0.0/16`, public 서브넷 ×2 · private 서브넷 ×2 (AZ 2a · 2b), IGW, 라우팅 테이블, 기본 보안 그룹 잠금 | 1번 만들고 유지 (모두 **무료**) |
| 앱 | `infra/modules/aws/` | 보안 그룹, ALB, ECS, IAM 실행 역할, 로그, (비밀값, RDS) | 매 배포 · 앱을 지우면 같이 지워요 |

- 앱 모듈은 `vpc_id`, `public_subnet_ids`, `private_subnet_ids`를 **필수 변수**로 받아요. 값은 대상 환경 등록값(`targets/aws.json`)에서 와요. `daisy-bootstrap`(§12-8)이 네트워크를 만들고 나서 자동으로 넣어 줘요
- 대역은 온프레미스(`172.16.1.0/24` · `172.16.2.0/24`, §16-2)와 겹치지 않아서 나중에 VPN을 붙일 수 있어요
- NAT Gateway는 여전히 없어요. private 서브넷은 DB 전용이라 인터넷 경로가 없어요
- 앱이 여러 개여도 VPC 하나를 같이 써요 (리전당 VPC 기본 5개 제한을 피해요)

### 5-1. 구성

```
인터넷 ──80──▶ ALB (public 서브넷 ×2, SG: 80 from 0.0.0.0/0)
                 │ target group (ip, port, healthcheck)
                 ▼
              ECS Fargate 태스크 (public 서브넷 + 공인 IP, SG: port from ALB SG만)
                 │ 아웃바운드 → 레지스트리에서 이미지 pull (NAT 없이)
                 ▼ (database: true 일 때만, S)
              RDS PostgreSQL (private 서브넷 ×2, SG: 5432 from 앱 SG만)
```

NAT Gateway 없이 이미지를 받으려고 태스크를 public 서브넷에 두고 공인 IP를 붙여요. 인바운드는 ALB SG에서만 허용해서 태스크가 직접 노출되지 않아요.

### 5-2. 리소스

| 묶음 | 리소스 | 조건 |
|---|---|---|
| 네트워크 | 만들지 않아요. 고정 네트워크의 VPC · 서브넷 ID를 받아요 (§5-0) | — |
| 보안 그룹 | ALB SG, 앱 SG | 항상 |
| 로드밸런서 | `aws_lb`, `aws_lb_target_group`, `aws_lb_listener`(80) | 항상 |
| 실행 | `aws_ecs_cluster`, `aws_ecs_task_definition`, `aws_ecs_service`, `aws_cloudwatch_log_group` | 항상 |
| 권한 | 실행 역할 `aws_iam_role` + `AmazonECSTaskExecutionRolePolicy` + 자기 비밀값 읽기 인라인 정책 | 항상 (인라인은 비밀값이 있을 때) |
| 비밀값 | `aws_secretsmanager_secret` + `_version` (키마다) | `secrets`가 있을 때 |
| DB (S) | `aws_db_subnet_group`(고정 private 서브넷), DB SG, `aws_db_instance` | `database = true` |

DB 접속 정보는 앱에 환경변수로 넣어요. 이름은 온프레미스·GCP와 같아야 해서 황지환과 맞춰요 (D-6): `(가칭)` `DB_HOST`, `DB_PORT`, `DB_NAME`, `DB_USER`는 일반 환경변수, `DB_PASSWORD`는 RDS 관리 비밀값(`manage_master_user_password = true`)에서 읽어요.

### 5-3. 구현할 때 주의할 점

1. **Fargate cpu·memory 조합**: 0.25 vCPU → 512/1024/2048, 0.5 → 1024/2048, 1 → 2048만 허용 (비용 상한 안에서). 변수 검증으로 막아요
2. **target group**: `target_type = "ip"`, 헬스체크 `interval = 10`, `healthy_threshold = 2`, `matcher = "200"`. **`deregistration_delay = 30`** (기본 300초면 교체 배포가 5분 넘게 걸려요)
3. **`aws_ecs_service`**: `assign_public_ip = true`(없으면 `CannotPullContainerError`), `wait_for_steady_state = true`, `deployment_circuit_breaker { enable = true, rollback = true }`. 그래서 **apply 성공 = 헬스 통과**예요. 새 태그가 헬스에 실패하면 자동 롤백되고 apply는 실패로 끝나요
4. **Secrets Manager `recovery_window_in_days = 0`**: 아니면 destroy 후 같은 이름으로 다시 만드는 게 최대 30일 막혀요
5. **sensitive map은 `for_each`에 못 써요**: `for_each = nonsensitive(toset(keys(var.secrets)))`
6. **RDS (S)**: `storage_encrypted = true`, `multi_az = false`, `publicly_accessible = false`, `skip_final_snapshot = true`, `deletion_protection = false`, `backup_retention_period = 0`(생성 시간 단축). 생성에 5~10분 걸려요
7. **비공개 이미지**: `sample-monolith`의 GHCR 패키지는 9/30 익명 조회에서 **403(비공개)**이었어요. 이대로면 ECS가 pull하지 못해요 (D-12). VM 단계에서는 Jenkins CI가 개인 Docker Hub **공개** 저장소로 푸시해서 피해 가요
8. (S) 가능하면 write-only 인자(`secret_string_wo` 등)로 비밀값이 state·plan에 남지 않게 해요. provider 지원 여부는 착수 시 확인해요

### 5-4. 완료 기준

- [x] `terraform fmt -check`, `terraform init -backend=false && terraform validate` 통과 (9/30, aws 6.66.0)
- [x] `sample-monolith` 값으로 `plan` 성공. 리소스가 §5-2 표와 같고 NAT·RDS 없음 (9/30, Jenkins CD #1, 개인 계정 `PLAN_ONLY`: 22개 생성)
- [ ] (사람 확인 후) `apply` → `curl ${service_url}/health` 200, `smoke-test.sh` 통과, `/version`의 `commit` = `image_tag` — **팀 계정에서**
- [ ] **`image_tag`만 바꾼 `plan`이 task definition 교체(`-/+`)와 service 변경(`~`)만 보여줌** (네트워크·ALB 변경 0 → N-08 "컨테이너만 교체" 확인) — apply한 state가 있어야 해서 **팀 계정에서**
- [x] R-1~R-6 수동 확인 (9/30 plan JSON: `0.0.0.0/0` 인바운드는 ALB 80 하나, 앱은 ALB SG에서만, NAT·RDS·EIP 0개). 정적 검사 도구(`checkov`·`trivy config`)는 아직
- [ ] (사람 확인 후) `destroy` 후 `Project=daisy` 태그 리소스 0개 — **팀 계정에서**

---

## 6. GCP 기준 모듈 (N-03)

### 6-1. 구성

```
인터넷 ──443──▶ Cloud Run 서비스 (allUsers invoker, 전용 SA)
                   │ startup probe: healthcheck
                   └─ Secret Manager (secrets가 있을 때, SA는 자기 비밀값만 읽기)
```

### 6-2. 리소스

| 리소스 | 조건 |
|---|---|
| `google_service_account` (런타임 전용, `daisy-{name}-run`) | 항상 |
| `google_cloud_run_v2_service` | 항상 |
| `google_cloud_run_v2_service_iam_member` (`allUsers`, `roles/run.invoker`) | 항상 (공개) |
| `google_secret_manager_secret` + `_version` + `_iam_member`(secretAccessor) | `secrets`가 있을 때 |
| Cloud SQL | `database = true` (S). 착수 시 방식 결정: private IP + Direct VPC egress가 R-3에 맞아요 |

### 6-3. 구현할 때 주의할 점

1. **`deletion_protection = false`**: google provider가 Cloud Run v2 서비스에 삭제 보호를 기본으로 켜서, 안 끄면 destroy가 실패해요
2. **`PORT` 환경변수는 넣지 않아요**: Cloud Run 예약어라 에러가 나요. `ports { container_port = var.port }`만 쓰면 Cloud Run이 `PORT`를 넣어 줘요 (HelloCalc는 `PORT`를 읽어요)
3. **레지스트리**: Cloud Run은 Artifact Registry와 **공개** Docker Hub·GHCR 이미지를 직접 받아요 (공식 문서, 9/30 확인). 공개 이미지는 최대 1시간 캐시돼요. **비공개 이미지만** Artifact Registry 원격 저장소가 필요해요 (D-3)
   - **Cloud Run은 amd64 이미지만 실행해요.** 그래서 CI는 `linux/amd64,linux/arm64`로 푸시해요 (§12)
4. **API 활성화는 bootstrap에서 1회** (`disable_on_destroy = false`). 모듈에서 켜면 destroy할 때 API가 꺼져서 다른 앱이 깨져요
5. **cpu 1 미만은 제약이 있어서** (동시성 1 등) 1로 올려요. `scaling { min_instance_count = 0 }`으로 요청이 없으면 과금 0
6. 기본 Compute SA를 쓰지 않고 전용 SA를 만들어요 (R-6)
7. 조직 정책(도메인 제한 공유)이 걸린 프로젝트면 `allUsers` 바인딩이 막혀요. 해커톤 프로젝트에 조직 정책이 없는지 먼저 확인해요

### 6-4. 완료 기준

§5-4와 같아요. 차이만 적으면:
- [ ] `image_tag`만 바꾼 `plan`이 `google_cloud_run_v2_service` 변경(`~`) 하나만 보여줌
- [ ] `service_url`이 `https://`로 시작하고 `/health` 200

---

## 7. state 백엔드 (N-07)

### 7-1. 구성 — 환경마다 그 환경의 저장소 + 잠금 (D-4)

**원칙: 각 환경의 state는 그 환경이 제공하는 저장소에 두고, 모두 잠금을 켜요** (2026-10-01, PR #17 답변).
- 한 환경의 장애나 자격증명 문제가 **다른 환경의 배포를 막지 않아요**
- 각 배포는 **자기 환경의 키만** 있으면 돼요 (최소 권한). GCP 배포에 AWS 키가 필요 없어요
- 환경마다 독립적이라 "같은 앱을 여러 환경에"(이식성)라는 주제와 맞아요

| 환경 | 저장소 | 잠금 | 앱·웹 화면 표시 |
|---|---|---|---|
| AWS | S3 버킷 `daisy-tfstate-<계정 ID>` (`ap-northeast-2`) | S3 네이티브 잠금 `use_lockfile = true` (DynamoDB 없음) | S3 (잠금) |
| GCP | GCS 버킷 `daisy-tfstate-<프로젝트 ID>` (`asia-northeast3`) | GCS 자동 잠금 (설정 없음) | GCS (잠금) |
| 온프레미스 | `[미정]` 황지환과 결정. 후보: Jenkins VM 로컬 디스크(자동 잠금, VM이 고장 나면 유실) · PostgreSQL `pg` backend(자동 잠금) · MinIO(S3 호환) | 후보 모두 지원 | 결정 후 |

| 항목 | 값 |
|---|---|
| key | 지금 구현: `{app}/{env}/terraform.tfstate` (예: `hellocalc/aws/terraform.tfstate`). **`(가칭)` 서버 ID 기준 `{project_id}/{target_id}/terraform.tfstate`로 바꿀 예정**이에요. 하은현과 확정해요. 서버 배포 잠금(`target_lock.state_key`)과 단위가 같아져요 |
| 보호 | 버전 관리 켬, 서버 측 암호화, 퍼블릭 액세스 전부 차단, 이전 버전 30일 후 만료. S3는 TLS 아닌 요청 거부 정책까지 |
| Git | state에는 비밀값이 들어 있어서 절대 커밋하지 않아요 |

**잠금이란**: terraform이 실행되는 동안 state에 "사용 중" 표시를 남겨서, 두 사람(또는 두 배포)이 동시에 같은 환경을 바꿔도 state가 꼬이지 않게 해요. 두 번째 실행은 `Error acquiring the state lock`으로 멈춰요. 이 위에 Jenkins의 `disableConcurrentBuilds()`와 서버의 `target_lock`이 한 겹씩 더 있어요.

### 7-2. bootstrap (환경당 1회, 사람이 apply)

| 폴더 `(가칭)` | 하는 일 |
|---|---|
| `infra/bootstrap/aws-network/` | **고정 네트워크** (§5-0). `daisy-bootstrap`으로 plan → 승인 → apply하고, 만든 ID를 `targets/aws.json`에 넣어요. 구현 완료 (10/1) |
| `infra/bootstrap/aws-state/` | **S3** state 버킷과 버킷 정책. 처음엔 로컬 state로 만든 뒤 `terraform init -migrate-state`로 같은 버킷의 `_bootstrap/terraform.tfstate`로 옮겨요 |
| `infra/bootstrap/gcp-project/` | API 활성화(`run`, `secretmanager`, `iam`, `storage` + 필요 시 `artifactregistry`, `sqladmin`)와 **GCS** state 버킷(버전 관리, 균일 버킷 수준 액세스, 공개 차단). bootstrap 자기 state도 같은 방식으로 버킷에 옮겨요. 비공개 이미지를 쓰게 되면 Artifact Registry 원격 저장소도 여기서 |

### 7-3. 완료 기준

- [ ] 버킷마다 버전 관리 · 암호화 · 퍼블릭 차단이 적용됨 (S3는 TLS 강제까지)
- [ ] 같은 환경 · 같은 key로 동시에 `plan` 두 개 → 두 번째가 `Error acquiring the state lock`
- [ ] AWS · GCP를 동시에 `plan` → 서로 기다리지 않음 (저장소가 달라요)
- [ ] GCP 배포에 AWS 자격증명이 필요 없음, 반대도 마찬가지
- [ ] bootstrap state도 버킷으로 옮겨져 로컬에 `*.tfstate`가 남지 않음

구현 상태: `tf-run.sh`는 지금 S3만 지원해요. GCS backend 분기와 환경별 버킷 변수(`TF_STATE_BUCKET_AWS` · `TF_STATE_BUCKET_GCP` 가칭)는 GCP 모듈 PR에서 넣고, 그때 CD의 `withCloud`에서 "GCP 배포에도 AWS 키" 조건을 지워요.

---

## 8. 결정이 필요한 것 · 모순

루트 `AGENTS.md` §6·§8 기준으로 분류했어요. **모든 항목이 모듈 구현을 막지는 않아요** (§2 원칙 덕분). 4단계는 21시 회의 안건이에요.

| # | 항목 | 현재 문서 | 붙여 준 설계 | infra 영향 | 단계 · 누구 |
|---|---|---|---|---|---|
| D-1 | CI/CD 도구 | ADR-004 GitHub Actions, `AGENTS.md` §12-4 `[미정]`, `sample-monolith`은 GitHub Actions로 동작 중 | **Jenkins (확정이라고 전달받음)** | infra가 VM에서 Jenkins CI·CD 프로토타입을 만들고 있어요 (§12). CI는 N-01(김도영)과 겹쳐요 | 4 · ADR·전역 문서 반영과 CI 담당 공유를 김도영에게 요청 |
| D-2 | terraform 실행 주체 | `server/AGENTS.md` §10: apply는 하은현, CLI 실행부는 김승환, Postgres 작업 큐 | Jenkins가 validate~apply | 모듈은 무관해요. Jenkins CD 프로토타입은 기준 모듈로 plan → 승인 → apply를 시연해요. 웹에서 부르려면 server가 Jenkins REST `buildWithParameters`를 호출해야 해요 | 4 · server 결정과 충돌, 회의 필요 |
| D-3 | 컨테이너 레지스트리 | `[미정]`, 지금은 GHCR | Docker Hub | ECS·Cloud Run 모두 **공개** GHCR·Docker Hub 이미지를 직접 받아요. 비공개면 인증을 넣어야 하고, GCP는 Artifact Registry 원격 저장소가 필요해요. **공개 저장소라면 어느 쪽이든 infra는 막히지 않아요.** Docker Hub는 익명 pull 횟수 제한이 있어요. VM 단계는 개인 Docker Hub 공개 저장소를 써요 | 4 · 회의 |
| D-4 | state 저장소 | `[미정]` | S3 등 | **환경마다 그 환경의 저장소 + 잠금** (AWS S3 · GCP GCS, 10/1 PR #17 답변, §7-1). 러너가 주입해서 모듈은 무관해요. 온프레미스 저장소와 key 형식은 남았어요 | 4 · 회의 확인, 온프레미스는 황지환, key는 하은현 |
| D-5 | `deploy.yaml` 확장 (`cpu`, `memory`, `instances`, 외부 공개) | 9/29 초안에 없음 | 기본값 적용, 필요 시 수정 | 모듈에 기본값 변수로 먼저 둬요. `deploy.yaml` 반영은 결정 후 | 4 · 회의 |
| D-6 | DB 접속 환경변수 이름 | 없음 | 없음 | 세 환경이 같은 이름을 넣어야 이식성이 지켜져요 | 2 · 황지환과 합의 |
| D-7 | 공통 변수·출력 (§3) | `infra/AGENTS.md` §4 (가칭) | — | 온프레미스 모듈과 통일 | 2 · 김승환·하은현에게 이슈로 공지 |
| D-8 | 인프라 저장소(검증된 스크립트 보관) | server N-08(김승환), plan은 레포 밖 작업 디렉터리 | 별도 Git 저장소, `onprem/`·`aws/`·`gcp/` | 폴더 안 모양을 기준 모듈과 같게 제안 | 3 · 김승환, 안 풀리면 회의 |
| D-9 | Jenkins 호스팅 위치·담당 | 없음 | 없음 | **팀원 서버 한 대가 Jenkins 러너이자 온프레미스 대상이에요.** 연결 전까지 Mac VM `daisy-runner`로 대신해요 (§12). 배포 자격증명과 온프레미스 대상이 한 기기에 모여서, 그 서버가 뚫리면 전부 노출돼요. 웹훅 수신은 외부 공개 방식 `[미정]`과 얽혀 있어요 | 4 · 서버 담당 팀원·회의 |
| D-10 | 일정 순서 | 전역 일정: N-03(GCP) D1, N-06(AWS) D2 | — | AWS를 먼저 하면 N-03이 D2로 밀려요 | 4 · 김도영에게 공유 |
| D-11 | 리전 | `infra/AGENTS.md` §6: AWS `ap-northeast-2`, GCP `asia-northeast3` `[미정]` | — | 기본값으로 써요. 변수라 바꾸기 쉬워요 | 4 · 회의 확인만 |
| D-12 | `sample-monolith` GHCR 패키지 공개 여부 | README: "비공개로 만들어질 수 있어요" | — | 9/30 익명 매니페스트 조회 결과 **403**. 이대로면 ECS·Cloud Run이 인증 없이 못 받아요 | 3 · 박승준·김도영에게 공개 요청 |

---

## 9. 일정 (내 기준)

| 날짜 | 할 일 | PoC |
|---|---|---|
| 9/30 (D1) | VM 러너 `daisy-runner` 구축(§12), Jenkins CI 실행, 개인 계정 준비, AWS 모듈 `database: false` validate·plan, §3 계약 공지 | N-06 착수 |
| 10/1 (D2) | Jenkins CD로 AWS plan → 승인 → apply → 스모크 테스트 → destroy, `image_tag` 교체 plan 확인. state 버킷 bootstrap. GCP 모듈 validate·plan·apply | N-06, N-07, N-03 |
| 10/2 (D3) | AWS + GCP 병렬 plan·apply로 state 분리 확인, 러너(Jenkins/server) 연동 지원, 여유 있으면 DB 경로 | N-07 |
| 10/3 | 동결. 데모용 재배포 확인, 정리 계획 | |

---

## 10. 폴더 구조

```
infra/
├─ SPEC.md                         이 문서
├─ modules/
│  ├─ aws/                         AWS 기준 모듈 (루트 모듈)
│  │  ├─ main.tf                   terraform · provider 블록 포함, backend 없음
│  │  ├─ variables.tf
│  │  ├─ outputs.tf
│  │  ├─ .terraform.lock.hcl       커밋 (provider 버전 고정)
│  │  └─ hellocalc.tfvars.example  sample-monolith 값 예시 (비밀값 없음)
│  ├─ gcp/                         같은 구조
│  └─ onprem/                      황지환
├─ bootstrap/  (가칭)              사람이 1회 apply (daisy-bootstrap)
│  ├─ aws-network/                 고정 VPC · 서브넷 (§5-0)
│  ├─ aws-state/
│  └─ gcp-project/
├─ jenkins/    (가칭)              Jenkins 러너 (§12)
│  ├─ setup-runner.sh              Ubuntu 24.04 러너 설치 (VM · 팀원 서버 공용)
│  ├─ ci.Jenkinsfile               빌드 · 테스트 · 멀티 아키텍처 푸시
│  ├─ cd-plan.Jenkinsfile          병렬 plan → 승인 대기 (daisy-cd-plan)
│  ├─ cd-apply.Jenkinsfile         승인한 plan apply → 헬스체크 (daisy-cd-apply)
│  └─ render-tfvars.py             deploy.yaml → 변수 JSON
└─ scripts/    (가칭)
   └─ tf-run.sh                    §3-4 러너 규약 참고 구현
```

PR은 300줄 이하로 나눠요: ① 이 명세 ② bootstrap ③ AWS 모듈 ④ GCP 모듈.

---

## 11. 이 명세로 코딩하는 에이전트에게

- 작업 전에 루트 `AGENTS.md`(머지 전이면 루트 `CLAUDE.md`), `infra/AGENTS.md`, 이 파일을 읽어요
- **수정해도 되는 곳**: `infra/modules/aws/`, `infra/modules/gcp/`, `infra/bootstrap/`, `infra/jenkins/`, `infra/scripts/`, `infra/SPEC.md`. 그 밖은 이슈 초안만 만들어요
- **`terraform apply`·`destroy`, `aws`·`gcloud`의 생성·삭제 명령은 사람 확인 없이 실행하지 않아요.** `fmt`·`validate`·`plan`은 괜찮아요
- **`TF_RUN_APPROVED`를 직접 설정하지 않아요.** 사람의 Jenkins `input` 승인 뒤에만 쓰는 값이에요
- `*.tfvars`, `*.tfstate`, 키 파일을 만들거나 커밋하지 않아요. 예시는 `*.tfvars.example`에 비밀값 없이
- 검증은 실제 명령 결과를 붙여요. 건너뛴 단계가 있으면 그렇다고 적어요
- 구현이 끝나면 이 명세를 실제 코드에 맞게 고쳐서 같은 PR에 넣어요
- §3 계약(변수·출력 이름)을 바꾸면 김승환·하은현·황지환에게 알리는 이슈 초안을 같이 만들어요

---

## 12. Jenkins 러너 (VM 프로토타입) `(가칭)`

원래 팀원 서버 한 대가 Jenkins 러너이자 온프레미스 배포 대상이에요 (D-9). 연결되기 전까지는 **Mac의 VMware Fusion VM이 같은 역할**을 해요. 붙여 준 배포 과정(Jenkins CI + CD)을 여기서 끝까지 돌려요. 설치 스크립트와 Jenkinsfile을 레포에 둬서 서버로 그대로 옮겨요 (§13).

### 12-1. VM `daisy-runner`

| 항목 | 값 | 이유 |
|---|---|---|
| OS | Ubuntu Server 24.04 LTS **arm64**, 데스크톱 없음 | Apple Silicon Fusion은 ARM64 게스트만 돼요. 구독이 필요 없고 Jenkins·Docker·HashiCorp·Google apt 저장소가 모두 지원해요 |
| CPU / RAM | 4 vCPU / 4GB + swap 4GB | Mac이 8GB라서 4GB를 남겨요. docker build와 병렬 plan을 버텨요 |
| 디스크 | 40GB, 필요한 만큼만 늘어나는 방식 | 이미지·provider 캐시 포함 15~20GB 예상 |
| 네트워크 | NAT | Mac에서 VM IP로 SSH·Jenkins UI(8080)에 접속해요. 밖에서는 보이지 않아요. GitHub 웹훅이 못 들어와서 수동 실행해요 |
| 스냅샷 | `base` (Jenkins 초기 설정 직후) | 꼬이면 되돌려요 |

### 12-2. 파일

| 파일 | 하는 일 |
|---|---|
| `infra/jenkins/setup-runner.sh` | Java 21, Jenkins LTS, Docker CE + buildx(`daisy-builder`), qemu, terraform(버전 고정·hold), AWS CLI v2, gcloud CLI를 설치해요. 여러 번 실행해도 안전해요 |
| `infra/jenkins/ci.Jenkinsfile` | 앱 checkout → 테스트(`golang` 컨테이너에서 `make check`) → `linux/amd64,linux/arm64` 이미지 → 푸시 (태그 = 커밋 해시 40자) → 선택 시 CD 호출 |
| `infra/jenkins/cd-plan.Jenkinsfile` | `daisy-cd-plan`: 환경 선택 → 인프라 코드 확인 → **병렬 plan** → 위험 검사 → plan 요약(`plan-summary.json`) → 승인 대기 |
| `infra/jenkins/cd-apply.Jenkinsfile` | `daisy-cd-apply`: **시작 = 승인**. 승인한 plan(`PLAN_BUILD`)만 **병렬 apply** → 헬스체크·스모크 테스트 |
| `infra/jenkins/render-tfvars.py` | `deploy.yaml` + 대상 환경 등록값 + 이미지 주소 → 변수 JSON (프로토타입용 최소 변환) |
| `infra/scripts/tf-run.sh` | §3-4 러너 규약 참고 구현 |

### 12-3. Jenkins 설정 (UI에서 1번)

- **Job**: `daisy-ci`, `daisy-cd-plan`, `daisy-cd-apply` (예전 `daisy-cd`는 비활성)
  - 둘 다 "Pipeline script from SCM"으로 만들어요. 레포는 `https://github.com/Softbank-Hackathon-2026-Team-Daisy/daisy.git`
  - Script Path는 각각 `infra/jenkins/ci.Jenkinsfile`, `infra/jenkins/cd-plan.Jenkinsfile`, `infra/jenkins/cd-apply.Jenkinsfile`
  - 브랜치는 머지 전에는 작업 브랜치, 머지 후에는 `main`
  - `daisy`와 `sample-monolith` 둘 다 공개 레포라 GitHub 자격증명은 필요 없어요
- **Credentials**: `aws-deployer`, `gcp-deployer`, `registry` (§3-5)
- **전역 환경변수 (선택)**: `TF_STATE_BUCKET`, `EXPECTED_AWS_ACCOUNT`, `EXPECTED_GCP_PROJECT`. 계정 ID라서 레포에 두지 않아요
- **대상 환경 등록**: `/var/lib/jenkins/daisy-work/targets/gcp.json`에 `{"project_id": "<id>", "region": "asia-northeast3"}`를 넣어요. `aws.json`은 선택이에요 (없으면 모듈 기본값)
- **Executors**: 2 (CD가 승인을 기다리는 동안에도 CI를 돌릴 수 있게)
- **플러그인**: 권장 플러그인에 더해 **"Pipeline: REST API"**(`pipeline-rest-api`)가 필요해요. 서버가 단계별 상태(`wfapi/describe`)와 승인 대기(`wfapi/pendingInputActions`)를 읽을 때 써요. 최근 권장 플러그인에는 빠져 있어요. UI(Plugins → Available)에서 설치하거나 아래처럼 설치해요
  ```bash
  sudo -u jenkins java -jar jenkins-plugin-manager.jar --war /usr/share/java/jenkins.war \
    --plugin-download-directory /var/lib/jenkins/plugins --plugins pipeline-rest-api
  sudo systemctl restart jenkins
  ```
- **서버 연동용 API 토큰**: 서버가 Jenkins REST API(빌드 시작 · 로그 · 단계 · 승인)를 부를 때 Jenkins 사용자의 API 토큰을 써요. 토큰으로 인증하면 CSRF crumb은 필요 없어요. 10/1 러너에서 확인한 호출 흐름은 PR #17 코멘트(2번)에 있어요

### 12-4. MOCK과 빈 곳

| 단계 | 상태 | 진짜 담당 |
|---|---|---|
| CD "Infra code" | `MOCK`: AI 생성 대신 기준 모듈을 그대로 써요 (재사용 경로와 같아요) | 김승환 (N-02) |
| CD "Risk check" | `MOCK`: 통과로 처리. AI 수정·재시도도 없어요 | 김승환 (N-05) |
| `render-tfvars.py` | 최소 변환. `env` 값과 `secrets`는 넘기지 않아요 | 김승환 (`server/manifest`) |
| 온프레미스 | 선택지 없음 | 황지환 |
| 웹 화면 연동 | 없음. "Build with Parameters"로 수동 실행해요 | 하은현 (D-2) |

### 12-5. 개인 계정 단계

**10/1 변경: 개인 AWS 계정을 실제 환경으로 써요** (비용은 정산 예정). 아래 "plan까지만" 원칙은 9/30 ~ 10/1 오전 기록이에요.
- 실제로 만들 때는 `daisy-deployer`에 생성 권한(지금은 `AdministratorAccess`, 나중에 §3-5로 축소)이 있어야 하고, Jenkins `PLAN_ONLY`를 `0`으로 바꿔요. 둘 다 사람이 확인하고 바꿔요
- 비용은 계속 줄여요: 고정 네트워크는 무료, 앱(ALB · Fargate)은 쓰지 않을 때 지워요. Zero spend budget 알림은 켜 둬요

- **AWS: plan까지만 해요 (0원 보장, 9/30 ~ 10/1 오전)**
  - 개인 계정이 2025-07-15 이전 가입이라 12개월 프리티어가 끝났어요. ALB · Fargate · EC2 · 공인 IPv4가 모두 유료라, 리소스를 띄우는 순간 돈이 나와요
  - plan은 조회 API만 써서 아무것도 만들지 않아요. 모듈이 실제 AWS에서 맞는지와 Jenkins CD 흐름을 여기까지 검증해요
  - 보장 장치 세 겹:
    1. IAM 사용자 `daisy-deployer`에 **`ReadOnlyAccess`만** 줘요. 실수로 승인해도 AWS가 생성을 거부해요
    2. Jenkins 전역 환경변수 **`PLAN_ONLY=1`**: CD가 plan에서 끝나고, `tf-run.sh`도 apply · destroy를 막아요
    3. Billing → Budgets → **Zero spend budget**: $0.01만 나와도 메일이 와요
  - root에 MFA를 켜요. SSO · Organizations는 쓰지 않아요
  - apply → 헬스체크 → destroy는 **팀 계정(₩300,000 지원금)**에서 해요. 그때 `PLAN_ONLY`를 지우고 `daisy-deployer` 권한을 §3-5로 바꿔요
- **GCP**:
  - 프로젝트를 만들고 결제 계정을 연결해요 (프리티어도 결제 계정이 필요해요). 예산 알림도 설정해요
  - SA `daisy-deployer` 키를 발급해요. 조직이 없는 개인 계정이라 키 생성 제한 정책이 없어요
- **Docker Hub**: 개인 계정에 **공개** 저장소를 만들고 쓰기 토큰을 발급해요. ECS·Cloud Run이 인증 없이 pull해요
- **키 파일**: Jenkins에 올린 뒤 Mac에서 지워요

### 12-6. 주의

- VM에 4GB보다 많이 주지 않아요. 빌드할 때는 Mac의 다른 무거운 앱을 닫아요
- Ubuntu를 LVM으로 설치하면 루트가 디스크의 절반쯤만 잡혀요 (40GB 중 18.5GB). `sudo lvextend -r -l +100%FREE /dev/ubuntu-vg/ubuntu-lv`로 늘려요
- **VMware NAT DNS(`172.16.185.2`)는 EDNS 질의에 깨진 응답을 줘요.** Go로 만든 buildkit이 레지스트리 주소를 못 찾아서 빌드가 실패해요 (`lookup registry-1.docker.io ... no such host`). `setup-runner.sh`가 VMware 게스트에서만 Docker 컨테이너 DNS를 `1.1.1.1`·`8.8.8.8`로 지정해요 (`/etc/docker/daemon.json`)
- **Wi-Fi를 바꾸면 Mac의 Fusion NAT 서비스(`vmnet-natd`)가 꺼질 수 있어요.** Mac↔VM SSH는 되는데 VM에서 밖으로 못 나가면(`No route to host`) Mac에서 네트워크를 다시 켜요. VM은 켜 둔 채로 돼요
  ```bash
  sudo "/Applications/VMware Fusion.app/Contents/Library/vmnet-cli" --stop
  sudo "/Applications/VMware Fusion.app/Contents/Library/vmnet-cli" --start
  ```
- Mac이 잠들었다 깨면 VM 시계가 틀어질 수 있어요. AWS가 `RequestExpired`나 `SignatureDoesNotMatch`를 내면 VM에서 `timedatectl`을 확인해요
- Docker Hub는 익명 pull 횟수 제한이 있어요 (CI의 `golang` 이미지 등). 막히면 `docker login` 후에 받아요
- 로컬 state를 쓰는 동안 `/var/lib/jenkins/daisy-work/<app>/<env>/state/`를 지우면 만든 리소스를 destroy할 수 없어요
- **terraform이 도중에 강제 종료되면 state 잠금이 남을 수 있어요.** 다음 실행이 `Error acquiring the state lock`으로 막히면, 잠금을 건 실행이 정말 끝났는지 확인한 뒤 작업 디렉터리에서 `terraform force-unlock <잠금 ID>`로 풀어요. 그래서 apply 중에는 Jenkins에서 Abort하지 않아요

### 12-7. CD 두 Job: plan → 승인 → apply

10/1 결정: CD를 **준비(`daisy-cd-plan`)와 적용(`daisy-cd-apply`) 두 Job으로 나눠요.** §16-6의 "동일 job 대기·재개 vs 준비·적용 분리" `[미정]`을 분리로 정했어요. Jenkins `input`으로 기다리지 않아서 승인 대기 동안 executor를 잡지 않고, 승인은 서버 승인 API 하나로 받아요 (§16-6).

```
daisy-cd-plan #N ── 병렬 plan ── plan-summary.json ──▶ 서버: 승인 화면
                                                         │ 웹·앱에서 승인
                                                         ▼
daisy-cd-apply ◀── 서버가 buildWithParameters(PLAN_BUILD=N, APPROVAL_ID=apv_…)
   └ 승인한 plan만 병렬 apply → 헬스체크 · 스모크 테스트
```

| 항목 | 내용 |
|---|---|
| plan ID | `daisy-cd-plan-<빌드 번호>`. 서버는 빌드 번호(`PLAN_BUILD`)만 넘기면 돼요 |
| 작업 폴더 | plan마다 `$WORK_ROOT/$APP/$ENV/plans/<PLAN_ID>/` (`src/`, `vars.json`, `meta.json`, `summary.txt`). 새 plan이 승인 대기 중인 plan을 덮어쓰지 않아요 (§16-7 협의안) |
| 승인 화면 정보 | `GET /job/daisy-cd-plan/<N>/artifact/plan-summary.json` → `plan_id`, `image_tag`, `destroy`, 환경별 요약(`create=22` 등). 비밀값이 든 plan JSON은 보관하지 않아요 |
| 적용 대상 | apply Job이 그 plan ID의 폴더가 있는 환경을 스스로 찾아요. 승인한 plan에 들어간 환경만 적용해요 |
| 승인 기록 | `APPROVAL_ID` 필수 (서버 승인 ID `apv_…`, 사람이 직접 테스트할 때는 `manual-<이름>`). 없으면 실행하지 않아요 |
| 승인한 plan만 적용 | `meta.json`의 plan 파일 해시와 다르면 거부, 이미 적용한 plan이면 거부. 그사이 state가 바뀌었으면 terraform이 stale plan으로 거부 → 다시 plan · 승인 |
| 동시 실행 | 같은 앱·환경의 plan · apply는 `flock`으로 한 번에 하나만 (최대 10분 대기). 다른 앱·환경끼리는 동시에 돌아요 |
| 정리 | 적용하면 비밀값이 든 plan 파일을 지우고 `current`가 그 plan을 가리켜요. 하루 지난 plan 폴더는 다음 plan 때 지워요 |
| `PLAN_ONLY=1` | apply Job이 Verify 단계에서 거부해요 (개인 계정 0원 모드) |
| 삭제 | `daisy-cd-plan`에서 `DESTROY` 체크 → 삭제 plan → 승인 → `daisy-cd-apply` (헬스체크는 건너뛰어요) |

서버 연동 때 알아 둘 것:
- **같은 파라미터의 요청이 대기열에 겹치면 Jenkins가 하나로 합쳐요.** 같은 `Location`(대기열 주소)을 받아요 (10/1 확인)
- 승인 대기 API(`wfapi/pendingInputActions`)는 더는 쓰지 않아요. 승인은 apply Job 시작으로 대신해요

검증 (10/1, 러너):
- Jenkinsfile 3개 선언형 문법 검사 통과
- `tf-run.sh` 안전장치 10가지 확인: PLAN_ID 없음 · 형식 오류 · 없는 plan · **해시 불일치** · `PLAN_ONLY` · 승인 없음 · **이미 적용** · 같은 ID 덮어쓰기 · 적용 없이 output · **잠금 대기 초과**
- `daisy-cd-plan` 두 개를 동시에 실행 → plan 폴더 3개(`-1`~`-3`)가 이미지 태그·해시가 다른 채로 따로 남음. 잠금 때문에 순서대로 실행됨
- 실제 apply는 개인 계정 `PLAN_ONLY` 때문에 팀 계정에서 확인해요

### 12-8. 고정 리소스 bootstrap Job (`daisy-bootstrap`)

| 항목 | 내용 |
|---|---|
| 파일 | `infra/jenkins/bootstrap.Jenkinsfile` |
| 파라미터 | `STACK` (`aws-network`, 나중에 `aws-state`), `DESTROY` |
| 흐름 | `tf-run.sh <stack> plan` → **Jenkins에서 승인** → apply → (aws-network) VPC · 서브넷 ID를 `targets/aws.json`에 넣어요 |
| 승인 | 앱 배포와 달리 서버를 거치지 않는 관리자 작업이라 Jenkins `input`으로 승인해요. `PLAN_ONLY=1`이면 plan에서 끝나요 |
| 작업 폴더 · state | `$WORK_ROOT/_bootstrap/<stack>/` (plan마다 폴더 분리는 앱과 같아요). state key는 `_bootstrap/<stack>/terraform.tfstate` |
| 지울 때 | `DESTROY` 체크. 그 VPC를 쓰는 앱이 남아 있으면 AWS가 거부해요. 앱을 먼저 지워요 |

## 13. 팀원 서버로 옮길 때

- [ ] 개인 계정에 만든 리소스를 모두 destroy했는지 확인해요 (`terraform state list`가 비어 있음, `Project=daisy` 태그 리소스 0개)
- [ ] 서버의 OS·아키텍처를 확인해요 (`uname -m`). `setup-runner.sh`는 Ubuntu 24.04 기준이에요
- [ ] `sudo TERRAFORM_VERSION=<infra/AGENTS.md §2의 버전> bash infra/jenkins/setup-runner.sh`로 같은 버전을 설치해요
- [ ] 모듈의 `.terraform.lock.hcl`에 모든 플랫폼 해시가 있는지 확인해요: `terraform providers lock -platform=linux_arm64 -platform=linux_amd64 -platform=darwin_arm64`
- [ ] Jenkins Job 2개와 전역 환경변수, 대상 환경 등록, **"Pipeline: REST API" 플러그인**(§12-3)을 다시 준비해요
- [ ] Credentials를 **팀 계정** 값으로 넣어요. 권한은 §3-5로 줄여요
- [ ] 팀 계정에서 환경별 state 버킷 bootstrap(§7-2: S3 · GCS)을 다시 실행해요. 개인 계정 state는 옮기지 않아요 (비어 있어야 해요)
- [ ] 개인 IAM 사용자 키, GCP SA 키, Docker Hub 토큰을 폐기해요
- [ ] 개인 계정 ID·프로젝트 ID가 커밋이나 PR 본문(plan 출력)에 남지 않았는지 확인해요

## 14. 결정 기록

결정 기록은 루트 §6에 따라 **[`infra/AGENTS.md`](./AGENTS.md) §9**에 모아요 (#10). 온프레미스와 같은 표를 쓰고, 클라우드 혼자 정한 줄은 `[클라우드]`로 표시해요.

---

## 15. 변경 기록

| 날짜 | 내용 |
|---|---|
| 2026-09-30 | 초안 |
| 2026-09-30 | Jenkins 러너 VM 프로토타입(§12)과 서버 이전 체크리스트(§13) 추가. 공개 GHCR 직접 pull 사실 반영(D-3, §6-3), GHCR 비공개 확인(D-12), plan 파일 이름·state 잠금 권한 수정 |
| 2026-09-30 | 결정 기록을 `infra/AGENTS.md` §9로 옮김 (#10). `infra/CLAUDE.md` 참조를 `AGENTS.md`로 바꿈 |
| 2026-09-30 | AWS 기준 모듈 구현(§5, `database: false` 경로 우선). Google provider 제약을 `~> 8.0`으로 수정 (최신 8.5.0) |
| 2026-09-30 | 개인 AWS 계정은 plan까지만 (ReadOnlyAccess · `PLAN_ONLY=1` · Zero spend budget). CD에 `DESTROY`·`PLAN_ONLY` 추가 |
| 2026-10-01 | 온프레미스 명세(§16) 추가: 설치 현황, 데모 범위, 네트워크·HTTPS, Jenkins 실행·승인 합의, 미정 계약과 완료 기준 |
| 2026-10-01 | §16 보완: CI/CD VM 사양과 Zone 대역, 인프라팀 CI/CD 담당, 빌드·이미지 전달 검증, 작업 폴더·state 및 AI 생성·저장 협의 항목 |
| 2026-10-01 | state 저장소를 "환경마다 그 환경의 저장소 + 잠금"으로 변경(§7, D-4). "Pipeline: REST API" 플러그인 · 서버 연동 API 토큰(§12-3), 잠금 해제 방법(§12-6) 추가 |

---

## 16. 온프레미스 기준 모듈 (N-04)

담당: 황지환. 이 절은 현재 설치 현황과 10/1까지의 합의를 정리한 **구현 전 명세**예요. 실제 배포 검증 완료를 뜻하지 않아요.
규칙 변경은 `infra/docs-update-agents`의 `infra/AGENTS.md`에 따로 기록되어 있어요. 이 명세 브랜치는 main에서 시작했으므로 해당 변경은 아직 포함하지 않아요. 두 문서를 병합할 때 참조와 결정 상태를 맞춰요.

### 16-1. 목적과 확정 범위

온프레미스를 선택하면 클라우드와 같은 커밋 해시의 애플리케이션 이미지를 기존 Service VM에 배포해요.

- **Jenkins → Terraform → 사전 생성 Service VM의 Docker 컨테이너** 순서로 실행해요.
- 데모에서 VM 생성 시간을 제외하기 위해 VM과 Docker 실행 환경을 미리 준비해요. Terraform 자체를 제외하는 결정은 아니에요.
- 컨테이너의 관리 도구는 **Terraform**이에요. validate · plan → 사용자 승인 → apply 흐름을 유지해요.
- **Docker Compose는 사용자 검증용**이에요. 같은 컨테이너·네트워크·볼륨을 Terraform과 Compose 양쪽에서 관리하지 않아요.
- **Proxmox VM 자동 생성은 후속 목표**예요. 템플릿 복제·cloud-init으로 VM을 준비하고 현재 컨테이너 배포 앞에 연결하는 방향이에요.
- Site-to-Site VPN 없이 AWS는 API로, 내부 Service VM은 SSH 경로로 접근해요 (인프라 담당자 간 합의).

### 16-2. 실제 설치 현황

현재 설치 환경은 다음과 같아요. 자동 배포 검증 상태는 §16-8에서 별도로 관리해요.

| 항목 | 값 |
|---|---|
| Hypervisor | Proxmox VE 9.2.4 |
| Router / Firewall | pfSense CE 2.7.2 |
| Service VM OS | Ubuntu Server 24.04.2 LTS, live server amd64 |
| Service VM CPU | 2소켓 × 2코어 |
| Service VM 메모리 · 디스크 | 4GB · 64GB |
| Service VM 연결 | Bridge network, IP 수동 지정 |
| Service VM Gateway · DNS | 모두 `172.16.1.254` |
| Service Zone | `172.16.1.0/24` |
| CI/CD VM CPU | 2소켓 × 3코어, 총 6 vCPU |
| CI/CD VM 메모리 · 디스크 | 8GB · 80GB |
| CI/CD Zone | `172.16.2.0/24` |

Service VM의 실제 IP·bridge 이름과 Docker Engine 버전, CI/CD VM의 OS·아키텍처·IP·Gateway·DNS 및 Jenkins·Terraform 버전은 추가 확인해요. 위 VM 사양은 컨테이너별 CPU·메모리 제한과 구분해요.

### 16-3. 관리 범위와 사전 준비의 경계

| 구분 | 범위 · 상태 |
|---|---|
| Terraform 배포 대상 | 기존 Service VM의 앱 컨테이너. Docker provider 제품·버전은 `[미정]` |
| 이미지 | CI에서 생성한 커밋 해시 태그 이미지 사용. Registry 제품·접근 방식은 공동 합의 필요 |
| Docker 네트워크 · 볼륨 | 생성 개수·소유 범위·수명주기 `[미정]`. 추천안을 확정값으로 넣지 않아요 |
| DB | `database` 입력의 온프레미스 구현 범위·종류·데이터 보존 정책 `[미정]` |
| 사전 준비 | Proxmox VM, Docker 설치, IP·SSH 접근, pfSense·DNS·HTTPS 경로 |
| 배포 모듈 밖 | CI/CD VM, pfSense, 물리·가상 네트워크, 다른 앱과 사용자 검증용 Compose 리소스 |
| 후속 자동화 | Proxmox provider 선정, 템플릿·cloud-init, VM 생성·IP 할당·초기화 |

컨테이너 재배포나 정리 때문에 사전 생성 VM을 삭제하지 않아요. 관리할 네트워크·볼륨은 구현 전에 명시하고, 수동·Compose 리소스를 자동으로 가져오거나 덮어쓰지 않아요.

### 16-4. 네트워크와 접속 경로

동일한 Proxmox 물리 서버 안에서 Service VM과 CI/CD VM을 분리해요. Service Zone은 `172.16.1.0/24`, CI/CD Zone은 `172.16.2.0/24`로 확인했어요. 아래 bridge 연결은 구성안이며, 실제 연결·pfSense 라우팅·방화벽 규칙의 적용 상태는 별도로 검증해요.

| Bridge | 네트워크 | 용도 |
|---|---|---|
| `vmbr0` | External | 물리 네트워크 · pfSense WAN |
| `vmbr1` | `172.16.1.0/24` | Service Zone |
| `vmbr2` | `172.16.2.0/24` | CI/CD Zone |

```text
CI/CD VM의 Jenkins · Terraform
  ├─ AWS API → AWS 배포
  └─ pfSense 내부 라우팅 → SSH → Service VM의 Docker 관리

허용된 개발자 → WireGuard Client-to-Site → 허용된 내부 관리 대상
```

- Terraform은 CI/CD VM에서 실행해요. Docker provider가 SSH 경로를 통해 대상 Docker를 관리하도록 연결하며, 구체 설정은 provider 선정·검증 후 정해요.
- **Site-to-Site VPN은 이번 배포 구성에서 제외**해요. AWS API 기반 배포에 사설망 연결이 필요하지 않다는 판단이며, 짧은 마감 동안 터널·라우팅·CIDR 조정과 검증 부담을 줄여요.
- AWS API의 통신 암호화·인증·권한 관리와 개발자 WireGuard 접속은 별개예요. API 키를 가진 것만으로 모든 통신이 안전하다고 간주하지 않아요.
- Jenkins의 SSH 사용자·키 전달·호스트 확인·Docker 권한, 개발자 VPN 접근 대상과 권한은 `[미정]`이에요. 인증정보는 문서에 쓰지 않아요.
- 초기안의 AWS·Other Cloud VM 대역은 이번 확정 배포 경로의 필수 구성이 아니며, 기존 ECS·Cloud Run 구성을 변경하지 않아요.

### 16-5. 사용자 서비스 공개

```text
사용자 → Route 53에서 도메인 조회 → 온프레미스 공인 IP의 80 · 443
       → pfSense의 HTTPS 처리 · 내부 전달 → Service VM의 앱 포트
       → Docker 컨테이너
```

- Route 53에는 공인 IP를 연결해요. DNS에 `IP:포트`를 등록하는 방식이 아니에요.
- **Let's Encrypt 인증서를 pfSense에 적용**하는 방향으로 확정했어요. TLS 종료용 서비스, 인증서 발급·갱신, 80번 요청 처리, 내부 전달 프로토콜·포트는 `[미정]`이에요.
- 80·443은 앱 서비스 공개용이에요. pfSense 관리 화면이나 Docker 관리 API 공개를 뜻하지 않아요.
- 실제 도메인, DNS 관리 담당·권한, 공인 IP 변경 대응, Service VM의 호스트 포트와 컨테이너 내부 포트는 추가로 정해요.

### 16-6. Jenkins 실행과 서버 승인

10/1 서버·인프라 간 합의에 따른 목표 흐름이에요. §12의 기존 프로토타입이 이미 아래 방식으로 구현되었다는 뜻은 아니에요.

**애플리케이션 CI/CD의 구현·운영은 인프라팀이 담당하고, GitHub Actions 대신 Jenkins를 사용해요.** Jenkinsfile에 코드 가져오기·테스트·이미지 빌드·Registry 푸시와 Terraform 배포 단계를 정의해요. 서버는 Jenkins API로 작업을 요청하며 사용자 승인·상태·로그·결과를 연결해요. GitHub 이벤트와 CI의 연결 방식 및 CD 시작 조건은 별도로 맞춰요.

| 역할 | 담당 경계 |
|---|---|
| `daisy-ci` | GitHub 코드 가져오기 → 테스트·이미지 빌드 → 커밋 해시 태그로 Registry 푸시 |
| `daisy-cd` | AI 호출 → Terraform 생성 → validate·plan·검사 → 승인된 plan apply → 배포 확인 |
| 서버 | 사용자 요청·승인 API, Jenkins API 요청, 상태·로그·결과 연동 |
| 인프라 | Jenkins CI/CD 구현·운영과 환경별 배포 연결. AI 생성 로직의 개발 담당이 자동으로 이전되는 것은 아님 |

**사용자 승인은 웹·앱 → 서버 승인 API 하나로 받아요.** 실서비스에서는 Jenkins 별도 사용자 승인 단계를 두지 않아요.
plan을 먼저 생성해 검토 정보를 제공하고, 서버가 그 plan에 대한 승인을 받은 후 Jenkins에 적용을 요청해요. 승인 후 다른 plan을 새로 만들어 기존 승인으로 적용하지 않아요.

```text
Jenkins: Terraform 준비 → validate · plan · 위험 검사
  → 서버: plan 식별자 · 승인 정보 제공
  → 사용자: 웹 · 앱에서 서버 승인 API 호출
  → 서버: 승인된 plan 실행 요청
  → Jenkins: 해당 plan apply → 헬스체크 → 결과 전달
```

- 동일 job의 대기·재개인지, 준비 실행과 적용 실행을 분리할지는 `[미정]`이에요.
- plan 전달·식별, 로그 수신, 중단 요청 연결은 황지환·임채준이 맞춰 **10/1까지 공유하기로 한 항목**이에요. 공유 완료를 뜻하지 않아요.
- 구체 API·인증·작업 ID·중복 요청·재승인 처리는 서버와 맞춰요. 이 명세에서 임의의 endpoint를 확정하지 않아요.
- 기존 Jenkins `input`·`TF_RUN_APPROVED` 처리는 프로토타입 구현이에요. 서버 승인과 연결하는 구현 전까지 승인 검사를 단순 제거하거나 우회하지 않아요.

### 16-7. 입력 · 출력 · state 합의 사항

§3과 `infra/AGENTS.md` §4는 온프레미스 공통 계약 검토의 출발점이에요. 이 절 추가만으로 `(가칭)`을 승인하거나 `deploy.yaml`을 변경하지 않아요.

| 항목 | 온프레미스에서 정할 내용 |
|---|---|
| 이미지 | 공통 `image` · `image_tag` 사용 방향, Registry 인증·Pull 방식 |
| 포트 · 헬스체크 | 앱 내부 포트, VM 게시 포트, pfSense 전달 포트의 매핑과 명세의 HTTP 경로 |
| `env` · `secrets` | 전달 주체·주입 방식·민감값 취급 |
| CPU · Memory | VM 사양과 컨테이너 제한을 구분. 공통 변수 의미·단위·기본값 합의 |
| `database` | 지원 범위와 데이터 보존·삭제 정책 |
| 대상 호스트 | 사전 생성 VM IP를 Jenkins에 등록할 방식, SSH 인증과 Docker 접근 |
| `service_url` | 공통 출력 이름 유지 방향. 실제 주소 전달 주체·반환 시점·헬스체크 연결 합의 |
| state | 프로젝트·대상별 고정 주소와 잠금 기준을 협의. S3의 온프레미스 적용 여부 및 최종 키는 미정 |

출력 URL만으로 정상 배포를 판정하지 않아요. 컨테이너 상태와 HTTP 접근을 확인해요.
같은 컨테이너를 여러 state나 Compose와 중복 관리하지 않으며, 실제 관리 대상과 state의 대응을 구현 전에 정해요.

서버 측 작업 폴더·state 제안은 아래와 같아요. 방향에 대한 회의 의견은 있으나, 최종 키·잠금·전달 계약은 인프라와 서버가 확정해야 하므로 `(가칭)`으로 기록해요.

| 항목 | 협의안 `(가칭)` |
|---|---|
| 작업 폴더 | 배포 요청·대상·plan 변경마다 분리해 승인 대기 중인 파일을 덮어쓰지 않아요. 승인된 plan과 관련 실행 파일은 실행 완료까지 함께 보관해요 |
| state 주소 | 같은 프로젝트·대상은 고정 주소를 사용해요. 예시는 `{project_id}/{target_id}/terraform.tfstate`이며, 매번 달라지는 배포 ID를 state 키로 사용하지 않는 방향이에요 |
| 대상 식별 | `aws`처럼 클라우드 종류만으로 구분하지 않고, 같은 클라우드의 서로 다른 배포 대상도 구분해요 |
| 저장·잠금 | 온프레미스도 S3를 사용할지, 서버·Jenkins·backend가 동일 state를 기준으로 동시 변경을 제어할지 맞춰요 |
| 기존 state | 이미 사용하는 state가 있다면 키만 바꾸지 않고 이전 방법을 확인해요. §7의 기존 키 규약은 최종 합의 전 임의 변경하지 않아요 |
| 코드 재사용 | 같은 프로젝트·대상에서 manifest·기준 코드 버전·이미지 태그 외 입력의 변경을 비교해 재사용 가능 범위를 정해요 |

### 16-8. 완료 기준 초안과 검증 상태

아래는 앞으로 확인할 항목이며 **아직 통과한 항목이 아니에요.** 실제 변경을 수반하는 검증은 사람 승인 후 수행해요.

- [ ] Docker provider·버전과 관리할 컨테이너·네트워크·볼륨 범위 확정.
- [ ] Jenkins CI에서 GitHub 코드 가져오기·테스트·이미지 빌드 및 커밋 해시 태그의 Registry 푸시 성공.
- [ ] Service VM의 Docker에서 지정 이미지 Pull 성공. Registry 인증이 필요하면 인증 경로도 검증.
- [ ] CI/CD VM에서 사전 등록 Service VM의 Docker에 SSH 경로로 접근.
- [ ] 기준 모듈 fmt·validate 및 대상 호스트 plan 검증.
- [ ] 사용자 승인과 동일 plan 적용 연결 확인.
- [ ] 다른 배포 요청이나 새 plan이 승인 대기 중인 작업 파일을 덮어쓰지 않는지 확인.
- [ ] 지정한 커밋 해시 이미지 실행 및 HTTP 헬스체크 성공.
- [ ] 도메인을 통한 외부 HTTPS 접근 확인.
- [ ] 이미지 교체 재배포에서 사전 생성 VM이 유지되고 의도한 앱 변경만 발생.
- [ ] 배포 단계·실패 정보·접속 URL을 서버에 전달.
- [ ] 동시 배포·중단·실패 후 복구 및 데이터 보존 기준 합의·검증.
- [ ] 정리 작업이 해당 Terraform 소유 리소스에만 영향을 주고 VM·다른 앱·검증 환경은 유지.

구체 실행 명령은 provider와 연결 방식 검증 후 추가해요. §12 프로토타입의 AI 생성·위험 검사 MOCK과 온프레미스 미구현 상태를 완료로 바꾸지 않아요.

### 16-9. 남은 작업과 후속 목표

| 항목 | 상태 | 담당 |
|---|---|---|
| Docker provider 제품·버전 | 미정. 이전 추천 버전은 채택하지 않음 | 황지환 |
| 관리 리소스 범위 | 컨테이너 수·네트워크·볼륨·DB 상세 미정 | 황지환, 공통 계약은 임채준·서버 |
| VM 등록·접속 | 실제 IP·Docker 버전·SSH 사용자·키·호스트 확인·권한 미정 | 황지환 · 임채준 |
| 컨테이너 실행 설정 | 자원 제한·포트·env·secrets·재시작·헬스체크 상세 미정 | 황지환 · 서버 |
| 공개 경로 | 도메인·앱 포트·TLS 종료 서비스·인증서 갱신 미정 | 황지환, DNS 권한은 관련 담당자 |
| state·Registry | 팀 공통 결정 대기 | 인프라 · 팀 |
| 서버 ↔ Jenkins | plan·승인·로그·중단·결과 세부 계약 미정 | 황지환 · 임채준 · 서버 |
| GitHub ↔ Jenkins CI | 이벤트 연결 방식과 CI·CD 시작 조건 미정 | 인프라, 서버 연동은 서버와 협의 |
| AI 생성 범위·기준 코드 | HCL 직접 생성·수정인지 고정 코드의 입력 생성인지, 허용 파일·입력 범위, 기준 커밋·Terraform 버전·provider 잠금 파일 미정. 개발 담당 경계도 확인 | 김승환 · 임채준, 온프레미스 기준은 황지환 |
| 생성 코드 저장·전달 | 서버 측 PostgreSQL script 테이블 저장 제안. 별도 Git 저장 필요 여부와 DB에서 복원한 실행 파일을 Jenkins에 전달하는 방식 미정 | 서버 · 인프라 |
| 작업 폴더·state·재사용 | §16-7 협의안의 최종 키·잠금·파일 보관·기존 state 이전·재사용 판정 기준 미정 | 인프라 · 서버 |
| Proxmox VM 자동화 | 후속 목표. provider·템플릿·cloud-init·IP·초기화 방식 추후 선정 | 황지환 |

우선순위는 **기존 VM 접속과 Docker 관리 연결 → 모듈 계약 → plan·승인·apply → HTTPS·서버 결과 연동**이에요. VM 자동 생성은 데모의 선행 조건으로 두지 않아요.

### 16-10. 기존 절과의 관계

| 기존 기록 | 이번 온프레미스 명세와의 관계 |
|---|---|
| §8 D-1·D-2의 CI/CD·실행 주체 미정 | 10/1 전달된 합의는 Jenkins 실행·서버 승인 API 단일화. §16-6을 따르며 기존 구현·관련 파트 문서는 담당자가 동기화 |
| §1의 GitHub Actions 및 CI 담당 설명 | 최신 전달 합의는 애플리케이션 CI/CD를 인프라팀이 Jenkins로 담당하는 방향. §16-6에 기록하며 기존 설명은 담당자와 동기화 |
| §7의 앱·환경 기반 state 키 | §16-7에 프로젝트·대상 ID 기반 키 제안을 추가. 최종 계약 및 기존 state 이전을 확인한 후 동기화 |
| §8 D-9·§12의 러너와 온프레미스 대상이 한 서버라는 표현 | 물리 서버는 같지만 CI/CD VM과 Service VM은 분리하는 설계 |
| §3-4·§11·§12의 Jenkins 별도 승인 | 프로토타입 설명으로 유지. 실서비스 승인 목표는 §16-6, 연동 코드는 아직 변경하지 않음 |
| §12-4의 온프레미스 선택지 없음 | 기존 프로토타입 상태. 이 절은 온프레미스 구현 명세이지 기능 추가 완료가 아님 |
| §14 결정 기록 | AGENTS 변경은 별도 `infra/docs-update-agents` 브랜치의 `1561fa5`까지 기록. 병합 시 이 절과 일치시킬 것 |

기존 클라우드 리소스·일정·미정인 공통 변수의 결정을 이 절이 임의로 바꾸지 않아요.
| 2026-10-01 | CD를 `daisy-cd-plan` · `daisy-cd-apply` 두 Job으로 분리(§12-7). plan마다 작업 폴더 분리, 승인한 plan만 적용, 앱·환경별 `flock` |
| 2026-10-01 | 고정 네트워크 분리(§5-0, `infra/bootstrap/aws-network`, `daisy-bootstrap` §12-8). 앱 모듈은 VPC · 서브넷 ID를 받아요. 개인 AWS 계정을 실제 환경으로 변경(§12-5) |
