# AGENTS.md — infra/ (환경별 기준 Terraform 모듈 · 러너 · state)

담당: 황지환 (`jihwan77`, 온프레미스), 임채준 (`dlacowns21`, 클라우드 GCP · AWS, state 백엔드). 상태: v1 (온프레미스 내용 보완: 2026-10-01).

루트 `AGENTS.md`를 먼저 따라요. 이 파일은 `infra/`에만 해당하는 규칙을 더하고, 루트 하드 규칙(§4)을 느슨하게 하지 않아요.
두 담당자가 같이 쓰는 파일이에요. **양쪽에 영향을 주는 규칙은 두 담당자가 합의해야 확정**이고, 한쪽이 제안한 것은 `(가칭)`으로 둬요.
무엇을 만드는지는 `SPEC.md`에 있어요. 클라우드는 [`SPEC.md`](./SPEC.md)(임채준), 온프레미스 명세는 황지환이 추가해요. **여기서 작업하기 전에 해당 `SPEC.md`를 읽어요.**

## 1. 이 폴더가 하는 일

| 누가 | 무엇 | PoC |
|---|---|---|
| 황지환 | Proxmox Service VM 생성용 Terraform 기준 모듈, Docker 앱 배포 연동, 서비스 외부 공개. 기존 Docker 기준 모듈과의 공통 계약은 합의 필요 | N-04 |
| 임채준 | GCP 기준 모듈 (Cloud Run) | N-03 |
| 임채준 | AWS 기준 모듈 (ECS Fargate · ALB · RDS) | N-06 |
| 임채준 | state 백엔드 (환경별 분리 · 잠금), Jenkins 러너 프로토타입 | N-07 |

**기준 모듈** = 사람이 직접 만든 환경별 정답 Terraform이에요. AI 생성의 참고 템플릿이자 N-02가 실패했을 때의 대안이에요.

## 2. 기술 스택

| 항목 | 값 | 이유 |
|---|---|---|
| IaC | **Terraform** | ADR-003 |
| Terraform 버전 | **1.16.4** `(가칭)` | 러너 · AI 작성 규칙 · 모듈이 같은 버전을 써요. 모듈은 `required_version = ">= 1.11"` (S3 네이티브 잠금) |
| provider | AWS `hashicorp/aws ~> 6.0`, Google `hashicorp/google ~> 7.0`, 온프레미스: Proxmox provider · 버전 `[미정]` | 온프레미스는 VM 생성 범위에 맞춰 선정해요 |
| 온프레미스 런타임 | **Docker** | ADR-005 |
| 러너 | Ubuntu 24.04 + Jenkins LTS `(가칭)` | CI/CD 도구는 루트 `[미정]`. 임채준이 VM 프로토타입으로 검증 중이에요 (클라우드 `SPEC.md` §12) |

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

- Terraform은 Proxmox Service VM 생성을 맡기는 방향이에요. 기존 VM을 가져와 관리할지, 새 VM을 생성할지는 미정이에요.
- Docker Compose는 컨테이너 CPU·메모리 등 실행 설정에 사용할 예정이에요. 이전 개인 사전 검증 범위에서 팀 배포 연동 방향으로 확장하는 제안이며, 생성·전달·실행 방식은 아직 정하지 않았어요.
- VM 자원 할당과 컨테이너 자원 제한을 구분해요. 공통 `cpu`·`memory` 입력의 의미는 서버·클라우드 담당자와 합의해요.
- Docker Engine · Compose v2의 정확한 버전과 CI/CD VM의 실제 사양은 추가로 기록해요.
- 개발자 원격 접속은 WireGuard Client-to-Site 용도예요. 클라우드 Site-to-Site VPN의 도입·대역 합의와 구분해요.

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

### 온프레미스 네트워크 구성안

- 같은 Proxmox 물리 서버 안에서 Service VM과 CI/CD VM을 분리하는 설계예요.
- 기존 구성안은 `vmbr0`를 물리 네트워크 · pfSense WAN 연결, `vmbr1`(`172.16.1.0/24`)을 Service Zone, `vmbr2`(`172.16.2.0/24`)를 CI/CD Zone으로 사용해요. 실제 적용·검증 상태는 온프레미스 명세에 기록해요.
- Zone 간 통신은 pfSense를 경유하도록 설계해요. 같은 물리 서버라는 이유로 같은 VM이나 같은 네트워크로 취급하지 않아요.
- 클라우드 VM · CIDR · Site-to-Site VPN은 기존 클라우드 ECS · Cloud Run 설계를 대체하는 확정 사항이 아니에요.

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

### 온프레미스 연동 방향 `(공동 계약 합의 필요)`

- 황지환의 방향은 **서버가 Jenkins API로 요청 → CI/CD VM의 Jenkins가 Terraform과 배포 파이프라인 실행**이에요. 서버 직접 실행으로 적힌 기존 문서와 차이가 있으므로 서버·임채준과 실행 책임 및 승인·상태·결과 전달 계약을 맞춰요.
- Jenkins가 생성된 Service VM의 IP를 알아내는 방법, VM 준비 완료 확인, 접속 및 Compose 배포 방법은 미정이에요.
- Terraform으로 VM을 생성한 것과 앱 배포가 완료된 것을 구분해요. 공통 `service_url`의 생성 주체와 헬스체크 시점도 합의해요.
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

현재 Service VM은 수동 IP로 구성되어 있어요. 자동 생성 경로와 실행 명령은 아직 검증하지 않았으므로, 위 클라우드 실행 예시를 온프레미스에서 그대로 동작한다고 간주하지 않아요.

구현 전에 다음을 정하고 온프레미스 명세에 기록해요.

1. Proxmox provider·권한, VM 템플릿·노드·스토리지와 기존 VM 처리 방식.
2. 자동 생성 VM의 IP 할당과 Jenkins의 대상 IP 확인 방법.
3. Docker · Compose 설치 및 접속 사용자·인증 준비 등 VM 초기화 방식.
4. Jenkins의 Service VM 접속, Compose 설정 전달·실행 방법.
5. 앱 헬스체크, pfSense HTTPS 연동, 외부 접근 및 결과 URL 확인.

현재 수동 VM의 설치 현황과 Terraform 자동 생성·배포 검증 결과는 구분해서 기록해요.

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
| 2026-09-30 | `[클라우드]` CI는 `linux/amd64,linux/arm64`로 푸시해요 | Cloud Run은 amd64만 실행하고, 러너는 arm64예요 | 1 |
| 2026-09-30 | `[클라우드]` apply · destroy는 터미널 입력이나 Jenkins `input` 승인 뒤 `TF_RUN_APPROVED`로만 실행해요 | 인프라 변경은 반드시 사람 승인 (루트 §4-2) | 1 |
| 2026-10-01 | `[온프레미스]` Terraform 관리 대상은 Proxmox Service VM 생성 방향 | 실제 온프레미스 VM 환경을 코드로 구성. 기존 Docker 기준 모듈과의 계약은 별도 합의 필요 | 1 (담당 방향) |
| 2026-10-01 | `[온프레미스]` Route 53 → 공인 IP, 외부 80·443으로 앱 공개 | 터널 대신 공인 IP 기반 서비스 공개 방향 | 1 |
| 2026-10-01 | `[온프레미스]` Let's Encrypt 인증서를 pfSense에 적용 | HTTPS 인증서 처리 위치 결정. 발급·갱신·TLS 종료 구현은 미정 | 1 |
| 2026-10-01 | 서버는 Jenkins API 호출, CI/CD VM에서 Terraform 실행 `(가칭 · 공동 합의 필요)` | 황지환이 제시한 실행 방향. 서버의 기존 직접 실행 계약과 조율 필요 | 팀 합의 대기 |
| 2026-10-01 | `[온프레미스]` Compose로 컨테이너 실행 설정을 정의할 예정 | CPU·메모리 등 컨테이너 설정을 관리. 생성·실행 책임과 공통 입력은 미정 | 제안 |

## 10. 아직 정하지 못한 것

| 무엇 | 상태 | 누가 |
|---|---|---|
| §4 공통 규약 | 임채준 제안. 온프레미스에도 맞는지 확인 필요 | 황지환 |
| state 저장소 | S3 버킷 하나에 `{app}/{env}` key로 나누자는 제안. 온프레미스 state도 같이 둘지 | 팀 회의 · 황지환 |
| CI/CD 도구 · terraform 실행 주체 | Jenkins로 전달받았지만, server는 Spring이 직접 실행하기로 기록해 둠 | **팀 회의** |
| 컨테이너 레지스트리 | 루트 `[미정]` | **팀 회의** |
| 온프레미스 배포 방식과 Terraform의 관계 | Proxmox VM 생성 + Compose 앱 설정 방향. 기존 기준 모듈 계약 및 AI 생성 범위와 조율 필요 | 황지환 · 서버 · 임채준 |
| Jenkins 호스트 | 같은 Proxmox 물리 서버의 별도 CI/CD VM 방향. Service VM과 분리하며 실제 설치·운영 분담 확인 필요 | 황지환 · 임채준 · 서버 |
| Proxmox provider · VM 생성 기준 | provider 버전, 템플릿·노드·스토리지·VM ID, 기존 VM 관리 여부, 설치 사양의 기본값 적용 여부 | 황지환 |
| 자동 생성 VM IP · 초기화 | 현재 수동 IP. IP 할당·발견, Docker 설치, 접속 사용자·인증 준비는 미정 | 황지환 · 러너 담당 |
| Jenkins → Service VM 배포 | 접속·파일 전달·Compose 실행, 준비 완료 확인, 재배포·실패 처리 방식 미정 | 황지환 · 임채준 |
| Compose 계약 | 생성 담당, 이미지·env·secrets 전달, VM 자원과 컨테이너 제한의 구분 | 황지환 · 서버 · 임채준 |
| 서비스 HTTPS 상세 | pfSense + Let's Encrypt 방향. TLS 종료용 서비스, 발급·갱신, 80번 처리, 내부 프로토콜·포트 미정 | 황지환 |
| DNS · 공개 주소 계약 | 도메인·Route 53 관리 권한, 공인 IP 변경 대응, `service_url` 반환 주체·시점 | 황지환 · 임채준 · 서버 |
