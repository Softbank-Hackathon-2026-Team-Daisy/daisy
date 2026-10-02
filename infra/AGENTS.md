# AGENTS.md — infra/ (환경별 기준 Terraform 모듈 · 러너 · state)

담당: 황지환 (`jihwan77`, 온프레미스), 임채준 (`dlacowns21`, 클라우드 GCP · AWS, state 백엔드). 상태: v1 (온프레미스 내용 보완: 2026-10-01).

루트 `AGENTS.md`를 먼저 따라요. 이 파일은 `infra/`에만 해당하는 규칙을 더하고, 루트 하드 규칙(§4)을 느슨하게 하지 않아요.
두 담당자가 같이 쓰는 파일이에요. **양쪽에 영향을 주는 규칙은 두 담당자가 합의해야 확정**이고, 한쪽이 제안한 것은 `(가칭)`으로 둬요.
무엇을 만드는지는 `SPEC.md`에 있어요. 클라우드는 [`SPEC.md`](./SPEC.md)(임채준), 온프레미스 명세는 황지환이 추가해요. **여기서 작업하기 전에 해당 `SPEC.md`를 읽어요.**

## 1. 이 폴더가 하는 일

| 누가 | 무엇 | PoC |
|---|---|---|
| 황지환 | 사전 생성 Service VM의 Docker 컨테이너를 관리하는 Terraform 기준 모듈 구현 및 배포·재배포 검증 | N-04 |
| 황지환 | Proxmox 기반 Service VM 및 CI/CD VM의 기반 환경 준비, 서비스·CI/CD 네트워크 분리, pfSense 접근 제어, 개발자 WireGuard 접속 구성 | N-04 지원 |
| 황지환 | pfSense와 Let's Encrypt를 이용한 서비스 HTTPS 공개 및 외부 접근 검증. 도메인·Route 53 연결과 관리 권한은 클라우드 담당자와 협의 | N-04 |
| 임채준 | GCP 기준 모듈 (Cloud Run) | N-03 |
| 임채준 | AWS 기준 모듈 (ECS Fargate · ALB · RDS) | N-06 |
| 임채준 | state 백엔드 (환경별 분리 · 잠금), Jenkins 러너 프로토타입 | N-07 |
| 임채준 | **AI Terraform 생성 · 수정 루프 · 재사용** (`infra/ai/`, 9/30 회의에서 담당 변경) | N-02 · N-05 · N-08 |
| 황지환 · 임채준 | Jenkins의 온프레미스 배포 연결: SSH 접근, Terraform 실행 환경, 배포 결과·헬스체크 연동. 서버와 승인된 plan·로그·중단 요청 계약 협의 | N-04 · N-07 |

Proxmox VM 자동 생성은 후속 목표예요. 데모에서는 사전 준비한 VM에 Terraform으로 컨테이너를 배포해요. Jenkins 설치·운영의 세부 분담은 두 인프라 담당자가 협의해요. 위 표는 담당 범위이며, 구성·검증 완료를 뜻하지 않아요. 실제 설정과 검증 결과는 `SPEC.md`에 기록해요.

**기준 모듈** = 사람이 직접 만든 환경별 정답 Terraform이에요. AI 생성의 참고 템플릿이자 N-02가 실패했을 때의 대안이에요.

## 2. 기술 스택

| 항목 | 값 | 이유 |
|---|---|---|
| IaC | **Terraform** | ADR-003 |
| Terraform 버전 | **1.16.4** `(가칭)` | 러너 · AI 작성 규칙 · 모듈이 같은 버전을 써요. 모듈은 `required_version = ">= 1.11"` (S3 네이티브 잠금) |
| provider | AWS `hashicorp/aws ~> 6.0`, Google `hashicorp/google ~> 8.0`, 온프레미스: Docker provider · 버전 `[미정]` | 데모는 기존 VM의 컨테이너를 관리해요. Proxmox provider 선정은 후속 VM 자동 생성 범위예요. Google은 최신 8.x(10/1 기준 8.5.0) |
| 온프레미스 런타임 | **Docker** | ADR-005 |
| CI/CD | **Jenkins 확정**: `daisy-ci`, `daisy-cd-plan` → 승인 → `daisy-cd-apply` | 10/1 전달된 팀 합의. Terraform 실행은 CI/CD VM의 Jenkins가 맡아요 |
| 러너 OS | Ubuntu 24.04 기반 프로토타입 | 클라우드 `SPEC.md` §12 참고. 실제 CI/CD VM 사양과 도구 버전은 별도 기록해요 |

### 온프레미스 설치 현황과 설계 방향

아래 설치 현황은 황지환이 제공한 실제 설치값이에요. 호스트를 직접 조회해 검증한 기록은 아니며, 자동 생성·배포 완료를 뜻하지 않아요.

| 항목 | 실제 설치 현황 |
|---|---|
| Hypervisor | Proxmox VE 9.2.4 |
| Firewall / Router | pfSense CE 2.7.2 |
| Service VM OS | Ubuntu Server 24.04.2 LTS, live server amd64 |
| Service VM 자원 | 2소켓 × 2코어, 메모리 4GB, 디스크 64GB |
| Service VM 네트워크 | Bridge 연결, IP 수동 지정. 실제 bridge 이름과 VM IP는 별도 확인 |
| Gateway · DNS | 둘 다 `172.16.1.254` |

- **온프레미스 컨테이너 관리 도구는 Terraform으로 확정해요.** 데모는 사전 생성·초기화한 Service VM을 사용하고, Jenkins → Terraform → 기존 VM의 Docker 컨테이너 순서로 배포해요.
- VM 생성 시간을 데모에서 제외하되, 컨테이너에 대한 validate · plan → 사용자 승인 → apply 흐름은 유지해요. Proxmox VM과 Docker 설치는 데모 사전 준비이며, 자동 생성 완료로 표시하지 않아요.
- Docker Compose는 **사용자 검증용**이며 팀 배포 컨테이너의 관리 도구가 아니에요. Terraform 관리 대상과 검증용 컨테이너·네트워크·볼륨을 분리하고, 같은 리소스를 두 도구로 동시에 관리하지 않아요.
- 후속 목표는 Terraform의 Proxmox 템플릿 복제와 cloud-init 기반 VM 준비를 현재 컨테이너 배포 앞에 연결하는 것이에요. provider·버전과 템플릿·IP 상세는 별도로 정해요.
- VM 자원 할당과 컨테이너 자원 제한을 구분해요. 공통 `cpu`·`memory` 입력의 의미는 서버·클라우드 담당자와 합의해요.
- Docker Engine · Compose v2의 정확한 버전과 CI/CD VM의 실제 사양은 추가로 기록해요.
- WireGuard Client-to-Site VPN은 허용된 개발자의 원격 접속에만 사용해요. 온프레미스·클라우드 Site-to-Site VPN은 이번 배포 구성에서 제외해요 (황지환·임채준 합의).

## 3. 폴더 구조와 경계

```
infra/
├─ AGENTS.md          이 파일 (공통 규칙 · 결정 기록)
├─ SPEC.md            클라우드 명세 (임채준). 온프레미스 명세는 황지환이 추가
├─ modules/
│  ├─ onprem/         ← 황지환
│  ├─ aws/            ← 임채준
│  └─ gcp/            ← 임채준
├─ bootstrap/ (가칭)  고정 네트워크(aws-network) · state 버킷 등 1회 준비 ← 임채준
├─ ai/                AI Terraform 생성 · 수정 루프 · 재사용 ← 임채준
├─ jenkins/   (가칭)  러너 설치 · CI/CD 파이프라인 ← 임채준 (프로토타입)
└─ scripts/   (가칭)  tf-run.sh 등 러너 보조 ← 임채준
```

- **다른 담당자의 모듈 폴더는 고치지 않아요.** 필요하면 이슈로 요청해요 (루트 §9)
- `jenkins/`·`scripts/`가 온프레미스 배포까지 부르게 되면, 그 부분은 황지환과 같이 정해요

### 온프레미스 네트워크 구성안

- 같은 Proxmox 물리 서버 안에서 Service VM과 CI/CD VM을 분리하는 설계예요.
- 기존 구성안은 `vmbr0`를 물리 네트워크 · pfSense WAN 연결, `vmbr1`(`172.16.1.0/24`)을 Service Zone, `vmbr2`(`172.16.2.0/24`)를 CI/CD Zone으로 사용해요. 실제 적용·검증 상태는 온프레미스 명세에 기록해요.
- Zone 간 통신은 pfSense를 경유하도록 설계해요. 같은 물리 서버라는 이유로 같은 VM이나 같은 네트워크로 취급하지 않아요.
- AWS 배포는 CI/CD VM에서 AWS API를 호출하고, 내부 Service VM의 앱 배포는 Private IP로 SSH 접속해 수행해요. 온프레미스 내부 SSH는 pfSense 라우팅을 이용하며 VPN 터널을 요구하지 않아요.
- Site-to-Site VPN을 제외해 짧은 마감 동안 터널·상대망 라우팅·CIDR 조정 및 장애 분석 작업을 줄여요. 현재 AWS API 기반 배포에는 클라우드 사설망으로 직접 접속할 필요가 없다는 판단이에요. 앱 간 사설 통신 요구가 생기면 별도 검토해요.
- AWS API 통신은 HTTPS/TLS로 암호화하고, AWS 자격증명으로 요청을 서명하며 IAM 권한으로 허용 작업을 제한해요. **키 자체가 통신을 암호화하거나 안전을 보장하는 것은 아니에요.** 키는 Jenkins Credentials로 관리하고 코드·로그에 노출하지 않으며 필요한 권한만 부여해요.
- 근거: [AWS API 요청 서명](https://docs.aws.amazon.com/IAM/latest/UserGuide/reference_sigv.html), [HTTPS 요청과 자격증명 사용](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_credentials_temp_use-resources.html).
- 클라우드 VM · CIDR을 새로 통일하는 결정은 아니며, 기존 ECS · Cloud Run 모듈 범위는 유지해요.

## 4. 모든 기준 모듈의 공통 규약 `(가칭 — 황지환 확인 필요)`

server AI(김승환)와 러너가 환경에 상관없이 같은 방식으로 모듈을 다루게 해요. 클라우드 쪽 자세한 정의는 `SPEC.md` §3에 있어요.

| 항목 | 규약 |
|---|---|
| 파일 | `main.tf` · `variables.tf` · `outputs.tf` 3개짜리 **루트 모듈** (AI 생성본과 같은 모양) |
| backend | 모듈에 쓰지 않아요. 러너가 `backend.tf` + `-backend-config`로 주입해요 |
| 입력 변수 | `deploy.yaml` 키와 1:1: `name`, `port`, `healthcheck`, `env`, `secrets`, `database`. 여기에 `image`(태그 없는 주소), `image_tag`(필수, 커밋 해시)를 더해요 |
| 출력 | `service_url` (스킴 포함, 끝에 `/` 없음). 헬스체크 주소 = `service_url` + `healthcheck` |
| state | **환경마다 그 환경의 저장소**에 두고 잠금을 켜요 (AWS S3 · GCP GCS · 온프레미스 `[미정]`). key는 지금 `{app}/{env}/terraform.tfstate`이고, 서버 ID 기준 `{project_id}/{target_id}`로 바꿀 예정이에요 `(가칭)` |
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
- Terraform 실행은 Jenkins가 맡아요. 클라우드 `SPEC.md` §3-4의 검증·실행 흐름을 참고하되, 승인 연동은 아래 10/1 합의를 따라요. 기존 SPEC·서버 문서·프로토타입의 직접 실행 및 Jenkins 별도 승인 설명은 담당자별 후속 동기화가 필요해요.

### Jenkins 실행 · 승인 계약 (10/1 합의, 세부 연결은 미정)

- **서버는 Jenkins API로 요청하고, CI/CD VM의 Jenkins가 Terraform과 배포를 실행**해요. 배포 대상 위치·접속 설정은 Jenkins에서 관리하며 백엔드가 직접 대상 호스트를 제어하지 않아요.
- `daisy-ci`: 코드 → 테스트·이미지 빌드 → 레지스트리. `daisy-cd`: 이미지 → 온프레미스·AWS 배포. 기존 GCP 모듈 범위의 삭제를 뜻하지 않아요. (10/1 이후 `daisy-cd`는 `daisy-cd-plan` · `daisy-cd-apply` 두 Job으로 나뉘었어요, §9)
- AI 호출 → Terraform 생성 → validate/plan → apply → 배포 단계는 Jenkins CD job에서 실행해요. AI 로직의 개발 소유권 변경을 뜻하지는 않아요.
- **사용자 승인은 웹·앱 → 서버 승인 API 하나로 받아요.** 서버가 승인을 받은 뒤 Jenkins에 적용을 요청하며, 실서비스에서는 Jenkins의 별도 사용자 승인 단계를 두지 않아요.
- 승인 대상 plan을 먼저 생성·검토한 뒤 그 plan에 대한 승인으로 apply해야 해요. 승인 후 생성·변경한 plan을 이전 승인으로 실행하지 않아요. plan 준비와 승인 후 실행을 같은 job에서 대기·재개할지, 실행을 분리할지는 아직 미정이에요. → **10/1 분리로 정했어요**: 서버가 승인 후 `daisy-cd-apply`를 `PLAN_BUILD` · `APPROVAL_ID`로 시작하고, plan 해시가 다르거나 이미 적용한 plan이면 거부해요 (§9, 클라우드 `SPEC.md` §12-7)
- 승인된 plan 전달·식별, 로그 수신, 중단 요청의 연결 방식은 **황지환·임채준이 맞춰 10/1까지 서버에 공유**해요. 재계획 시 재승인, 요청 인증·중복 방지·작업 ID 연결도 상세 계약에 포함해요. → 빌드 시작 · 로그 · 단계 조회는 PR #17 코멘트로 공유했지만 CD 분리 **전** 기준이에요. 두 Job 기준과 중단 요청은 다시 공유해야 해요 (§10)
- 내부 Service VM 접근은 SSH를 사용해요. Terraform은 CI/CD VM에서 실행하고 Docker provider가 기존 Service VM의 Docker를 관리하도록 연결해요. SSH를 통한 provider 연결·인증·호스트 확인 방식은 선정한 provider에서 검증 후 확정하며, 원격 Compose 실행으로 대체하지 않아요.
- 데모 대상은 사전 등록한 VM IP를 사용해요. Docker 접근·준비 확인, 공통 `service_url`의 생성 주체와 헬스체크 시점은 합의해요.
- §4 공통 규약은 이번 온프레미스 설명만으로 승인된 것으로 취급하지 않아요.

### 온프레미스 서비스 공개 방향

- Route 53에서 서비스 도메인을 온프레미스 공인 IP로 연결할 예정이에요. DNS 레코드에 `IP:포트`를 넣는 방식이 아니에요.
- 외부 **80 · 443은 사용자 앱 서비스 요청용**이에요. Docker 관리 API나 pfSense 관리 화면 공개를 의미하지 않아요.
- HTTPS는 **Let's Encrypt 인증서를 pfSense에 적용해 처리**할 계획이에요. 인증서 발급·갱신 방식, TLS 종료용 서비스와 내부 전달 프로토콜·포트는 아직 정하지 않았어요.
- 공인 IP → pfSense → Service VM의 앱으로 이어지는 전달 경로를 구성해요. 단순 포트포워딩 설정만으로 인증서 처리까지 완료되었다고 보지 않아요.
- 도메인 · Route 53 레코드 관리 담당과 권한, 공인 IP 변경 대응은 관련 담당자와 합의해요.

## 7. 실행 방법

```bash
# 모듈 검증 (자격증명 필요 없음)
cd infra/modules/<env>
terraform fmt -check && terraform init -backend=false && terraform validate

# plan · apply는 러너로 해요. 작업 디렉터리는 레포 밖이에요 (클라우드 SPEC.md §3-4)
APP=hellocalc IMAGE_TAG=<커밋 해시 40자> infra/scripts/tf-run.sh aws plan
```

### 온프레미스 실행 준비

현재 Service VM은 수동 IP로 구성되어 있어요. 데모는 이처럼 사전 준비된 VM에 Terraform으로 컨테이너를 배포해요. 실행 명령은 아직 검증하지 않았으므로 위 클라우드 실행 예시가 온프레미스에서 그대로 동작한다고 간주하지 않아요.

구현 전에 다음을 정하고 온프레미스 명세에 기록해요.

1. Docker provider·버전, 관리할 컨테이너·네트워크·볼륨 범위.
2. 사전 준비 VM의 IP와 Docker 설치 상태, Jenkins의 대상 등록 방법.
3. CI/CD VM에서 Service VM으로 접근할 SSH 사용자·인증·호스트 확인과 Docker 권한.
4. 컨테이너 입력·state, plan 승인·apply, 이미지 태그만 변경하는 재배포 검증.
5. 앱 헬스체크, pfSense HTTPS 연동, 외부 접근 및 결과 URL 확인.

컨테이너 재배포 시 사전 생성 VM은 생성·삭제 대상에 포함하지 않아요. Compose 검증용 리소스도 Terraform 배포 대상과 분리해요.
후속 VM 자동 생성에서는 Proxmox provider, 템플릿·노드·스토리지, IP 할당과 cloud-init 초기화를 별도로 정해요. VM 준비와 컨테이너 배포의 검증 결과를 구분해서 기록해요.

## 8. AI 에이전트에게

- 이 폴더 밖은 건드리지 않아요. 필요하면 이슈로 요청해요 (루트 §9)
- 작업을 요청한 담당자의 모듈 폴더만 고쳐요
- `terraform apply` · `destroy`, 클라우드 CLI와 Docker 호스트의 생성 · 삭제 명령은 **사람 확인 없이 실행하지 않아요** (루트 §4-2). `fmt` · `validate` · `plan`은 괜찮아요
- `TF_RUN_APPROVED`를 직접 설정해 승인을 우회하지 않아요. 기존 프로토타입의 Jenkins `input` 승인은 실서비스의 서버 승인 API 연동으로 전환해야 해요. 승인된 plan과 연결된 실행 요청을 검증한 뒤에만 실행하도록 계약을 구현하며, 문서 변경만으로 기존 승인 검사를 제거하지 않아요.
  - 10/1 CD는 전환했어요: `input` 없이 **`daisy-cd-apply` 시작 = 승인**이에요 (`APPROVAL_ID` 필수, plan 해시 확인). 그래서 **에이전트는 `daisy-cd-apply`를 시작하지 않아요.** `input` 승인은 관리자 작업인 `daisy-bootstrap`에만 남아요
  - `daisy-cd-plan`은 plan만 만들어서 실행해도 되지만, `USE_AI`면 Claude API 비용이 들어요
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
| 2026-10-01 | state는 **환경마다 그 환경의 저장소**(AWS S3 · GCP GCS)에 두고 모두 잠금을 켜요. 온프레미스 저장소는 황지환과 결정 `(가칭 · 팀 회의 확인)` | 한 환경의 장애 · 자격증명 문제가 다른 환경 배포를 막지 않고, 각 배포는 자기 환경 키만 필요해요 (최소 권한). PR #17에서 앱(박승준)에 답변 | 4 |
| 2026-10-01 | `[클라우드]` Jenkins에 "Pipeline: REST API" 플러그인을 넣어요 | 서버가 단계별 상태 · 승인 대기 API(`wfapi`)를 써요. 최근 권장 플러그인에 빠져 있어요 | 1 |
| 2026-10-01 | CD를 `daisy-cd-plan`(plan · 위험 검사 · 요약)과 `daisy-cd-apply`(승인한 plan 적용 · 헬스체크) 두 Job으로 분리. 서버가 승인 후 `daisy-cd-apply`를 `PLAN_BUILD` · `APPROVAL_ID`로 시작해요 | Jenkins `input` 대기 없이 승인을 서버 승인 API 하나로 받고(§16-6), plan마다 작업 폴더를 분리해 승인 대기 plan을 덮어쓰지 않아요(§16-7). 승인 대기 중 executor를 잡지 않아요 | 2 (서버가 쓰는 계약, 하은현에게 공유) |
| 2026-10-01 | `[클라우드]` AWS 네트워크(VPC · 서브넷)는 `infra/bootstrap/aws-network`로 1번 만들어 두고, 앱 모듈은 `vpc_id` · `public_subnet_ids` · `private_subnet_ids`를 받아요 | 배포마다 VPC를 만들고 지우는 건 불필요한 반복이에요. 네트워크는 무료이고, 대역이 고정돼야 VPN · 여러 앱 공유가 돼요 | 2 (모듈 입력 변수 변경, 김승환에게 공유) |
| 2026-10-01 | `[클라우드]` 개인 AWS 계정을 실제 환경으로 써요 (비용 정산 예정). 9/30의 "개인 계정은 plan까지만" 결정을 대체해요 | 팀 계정이 없어요. 생성 권한 · `PLAN_ONLY` 해제는 사람이 확인하고 바꿔요 | 1 |
| 2026-10-01 | AI Terraform 생성 · 수정 루프 · 재사용 담당을 김승환 → **임채준**으로 (9/30 회의 합의). 코드는 `infra/ai/`, Jenkins `daisy-cd-plan`에서 실행해요 | Terraform 실행이 CI · CD 모두 Jenkins로 모였어요. 루트 `AGENTS.md` §5-1 · `server/AGENTS.md` 갱신 필요 (김도영 · 김승환) | 팀 합의 (임채준 전달) |
| 2026-10-01 | `[클라우드]` AI 생성은 `claude-opus-5-5` + 구조화 출력(파일 3개 JSON) + 프롬프트 캐시. 재사용은 입력 지문(vars.json · 기준 모듈 · 규칙) 비교, 시도는 환경당 총 3번 | 바뀌었는지는 규칙으로 판단하고 AI는 고치는 방법만 정해요. Opus 5.5는 도구 호출 강제를 지원하지 않아요 | 1 |
| 2026-10-01 | `[클라우드]` 러너의 Jenkins · Docker · terraform 패키지는 `apt-mark hold` | `setup-runner.sh`를 다시 돌렸을 때 Jenkins가 업그레이드 · 재시작돼 돌던 apply가 끊길 뻔했어요 | 1 |
| 2026-10-01 | `[클라우드]` `daisy-cd-plan`의 `USE_AI` 기본값은 `true`. `false`면 기준 모듈 그대로(`MOCK` 대안 경로) | 데모 경로가 기본이고, API 장애 · 비용 문제 때 바로 대안으로 돌려요 | 1 |
| 2026-10-01 | `[온프레미스]` 데모는 기존 VM의 Docker 컨테이너를 Terraform으로 관리 | VM 생성 시간을 제외하면서 팀의 plan·승인·apply 흐름 유지. 이전 VM 생성 우선 방향을 대체 | 1 |
| 2026-10-01 | `[온프레미스]` Proxmox 템플릿 복제·cloud-init 기반 VM 자동 생성은 후속 목표 | 데모의 컨테이너 배포와 VM 준비 자동화를 단계적으로 분리 | 1 |
| 2026-10-01 | `[온프레미스]` Route 53 → 공인 IP, 외부 80·443으로 앱 공개 | 터널 대신 공인 IP 기반 서비스 공개 방향 | 1 |
| 2026-10-01 | `[온프레미스]` Let's Encrypt 인증서를 pfSense에 적용 | HTTPS 인증서 처리 위치 결정. 발급·갱신·TLS 종료 구현은 미정 | 1 |
| 2026-10-01 | Jenkins CI·CD 확정, 서버는 Jenkins API 호출, CI/CD VM에서 Terraform 실행 | 전달된 서버 합의. 실행을 한곳에 모으고 대상 설정은 Jenkins에서 관리 | 팀 합의 (황지환 전달) |
| 2026-10-01 | 사용자 승인은 웹·앱 → 서버 승인 API로 단일화, 실서비스 Jenkins 별도 승인 없음 | 중복 승인 제거. 승인된 plan 전달·로그·중단 연결은 인프라 두 담당자가 10/1까지 공유 | 팀 합의 (황지환 전달) |
| 2026-10-01 | Site-to-Site VPN 제외, AWS는 API, 내부 Service VM은 SSH로 배포 | 사설망 연결 없이 배포 가능. 짧은 마감에 터널·라우팅 구성과 검증 부담 축소 | 황지환·임채준 합의 |
| 2026-10-01 | WireGuard 원격 접속은 허용된 개발자에게 제한 | 개발자 관리 접속을 서비스 공개 및 자동 배포 경로와 분리 | 황지환·임채준 합의 |
| 2026-10-01 | `[온프레미스]` Compose는 사용자 검증용, 배포 리소스 관리 주체는 Terraform | 기존 Compose 배포 제안을 대체. 같은 컨테이너·네트워크·볼륨의 이중 관리 방지 | 1 |
| 2026-10-02 | `daisy-cd-plan` · `daisy-cd-apply`가 서버 요청(`request_id` · `payload`)을 받고, 대상별 결과를 서버 콜백(`/internal/jenkins/callbacks`, `X-Daisy-Jenkins-Token`)으로 보내요. `state_identity`는 러너가 실제로 쓰는 state 위치 `(가칭 · 서버 확인, #35)` | 서버(PR #40)가 이미 이 형식으로 보내고 받아요. plan의 `script_id`가 서버가 정하는 ID라 산출물 폴링으로는 안 돼요 (클라우드 SPEC §12-9) | 2 (서버가 쓰는 계약, 김승환 · 하은현에게 공유) |
| 2026-10-02 | `[클라우드]` AWS 기준 모듈에 선택 입력 `domain` · `subdomain`: 있으면 `*.<domain>` 인증서로 HTTPS, Route 53 `<subdomain>.<domain>` → ALB, `service_url` = `https://…`. 비우면 지금처럼 ALB 주소(HTTP) | 시연을 `aws.unibloom.cloud`로 해요. 인증서 · 영역은 `aws-domain` 스택 것을 찾아만 써요 | 2 (모듈 입력 추가, 기본값이 있어 기존 호출 그대로) |
| 2026-10-02 | 온프레미스 앱 공개 주소는 **ngrok** (`onprem.unibloom.cloud` → 서비스 VM `172.16.1.5:18080`). 10/1 `[온프레미스]` pfSense + Let's Encrypt 방향을 대신해요. 데모 앱 포트는 백엔드(8080)와 겹치지 않게 18080 `(가칭 · 황지환 확인)` | 서비스 VM에 www · api용 ngrok 서비스가 이미 상시 실행 중이라 엔드포인트 하나 추가로 끝나요. 포트 개방 · 인증서 갱신이 필요 없어요 (임채준 · 황지환 10/2 함께 설정) | 1 |
| 2026-10-02 | `[클라우드]` GCP 기준 모듈(Cloud Run) 구현. 리전은 asia-northeast1(도쿄), 공개 도메인은 Cloud Run 도메인 매핑(`gcp.unibloom.cloud`), state는 GCS | 도메인 매핑이 서울을 지원하지 않아요. 로드밸런서 없이 0원에 가깝게 도메인을 붙여요. §6의 GCP 리전 `[미정]`(asia-northeast3)을 대신해요 | 1 |
| 2026-10-02 | 대상 환경 등록의 `public_url`: 모듈 밖에서 연결한 공개 주소(온프레미스 pfSense HTTPS). 러너가 헬스체크 · 서버 보고에만 쓰고 모듈 변수에는 넣지 않아요 `(가칭 · 황지환 확인)` | 온프레미스 모듈 출력은 내부 주소예요. 모듈을 바꾸지 않고 `onprem.unibloom.cloud`를 서버에 알려요 | 2 |

## 10. 아직 정하지 못한 것

| 무엇 | 상태 | 누가 |
|---|---|---|
| §4 공통 규약 | 임채준 제안. 온프레미스에도 맞는지 확인 필요 | 황지환 |
| state 저장소 | 방향은 "환경마다 그 환경의 저장소 + 잠금"(§9). **AWS S3 버킷은 아직 안 만들어서 state가 임채준 러너 VM 로컬에 있어요** → 다른 Jenkins와 공유 · 잠금이 안 돼요. **온프레미스 저장소**와 **key 형식**(`{project_id}/{target_id}`)도 남았어요 | 임채준(S3) · 팀 회의 확인 · 황지환(온프레미스) · 하은현(key) |
| 서버 ↔ Jenkins 세부 계약 | 10/2 Jenkins 쪽 구현(클라우드 SPEC §12-9): 서버 요청 · 대상별 콜백 · `state_identity` 규칙 · apply 대조. 서버 쪽 콜백 인증 · 공개 경로 · 빌드 기록 유입과 실제 연결 검증이 남았어요 (#35). apply 중단은 지원하지 않아요 | 임채준 · 서버(김승환 · 하은현) |
| 승인 전 plan과 승인 후 apply 연결 | 구조는 **두 Job으로 분리**해서 정했어요 (§9, 클라우드 SPEC §12-7). 서버 쪽 승인 ID 발급 · 재승인 · 중복 요청 처리와 서버 연결 구현이 남았어요 | 인프라 · 서버 |
| 컨테이너 레지스트리 | 루트 `[미정]` | **팀 회의** |
| 온프레미스 Docker 모듈 계약 | 기존 VM의 컨테이너를 Terraform으로 관리하는 방식 확정. provider·버전, 리소스 범위와 공통 입력·출력 매핑은 미정 | 황지환 · 임채준, 서버와 계약 공유 |
| Jenkins 호스트 | 같은 Proxmox 물리 서버의 별도 CI/CD VM 방향. Service VM과 분리하며 실제 설치·운영 분담 확인 필요 | 황지환 · 임채준 · 서버 |
| Proxmox provider · VM 생성 기준 (후속) | provider 버전, 템플릿·노드·스토리지·VM ID, 설치 사양의 기본값 적용 여부. 데모 필수 경로에서 제외 | 황지환 |
| VM IP · 초기화 | 데모는 수동 IP·Docker 사전 준비 및 Jenkins 대상 등록. 자동 IP 할당·cloud-init은 후속 범위 | 황지환 · 러너 담당 |
| Jenkins → Service VM 배포 | CI/CD VM의 Terraform에서 SSH 경유 Docker 접근을 검증. 사용자·키·호스트 확인·권한, 준비 확인, 재배포·실패 처리 상세 미정 | 황지환 · 임채준 |
| WireGuard 개발자 접근 | 허용 개발자, VPN 대역, 접근할 내부 대상·포트와 계정 회수 절차 | 황지환 |
| 컨테이너 설정 계약 | Terraform 입력으로 이미지·env·secrets·CPU·메모리 반영. 공통 변수의 의미와 기본값, Compose 사용자 검증 환경과의 분리 방법 | 황지환 · 서버 · 임채준 |
| 서비스 HTTPS 상세 | pfSense + Let's Encrypt 방향. TLS 종료용 서비스, 발급·갱신, 80번 처리, 내부 프로토콜·포트 미정 | 황지환 |
| DNS · 공개 주소 계약 | 도메인·Route 53 관리 권한, 공인 IP 변경 대응, `service_url` 반환 주체·시점 | 황지환 · 임채준 · 서버 |
