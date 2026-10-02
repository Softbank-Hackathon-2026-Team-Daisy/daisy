# GCP 기준 모듈 입력 변수. 이름은 deploy.yaml 키와 1:1이에요 (infra/AGENTS.md §4, SPEC §3-1). AWS 모듈과 같은 계약이에요

variable "name" {
  description = "앱 이름 (deploy.yaml name). 리소스 이름 접두사 daisy-{name}에 써요"
  type        = string

  validation {
    # 런타임 서비스 계정 ID 30자 제한 때문에 20자 이하 (daisy-{name}-run)
    condition     = can(regex("^[a-z][a-z0-9-]{1,19}$", var.name))
    error_message = "name은 소문자로 시작하는 2~20자(소문자·숫자·-)여야 해요."
  }
}

variable "image" {
  description = "태그 없는 이미지 주소 (예: docker.io/<계정>/hellocalc). Cloud Run이 직접 받으려면 공개 이미지여야 해요"
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9.-]+(:[0-9]+)?/[a-z0-9._/-]+$", var.image))
    error_message = "image는 태그 없는 이미지 주소여야 해요. 태그는 image_tag로 넘겨요."
  }
}

variable "image_tag" {
  description = "이미지 태그 = 커밋 해시. latest는 쓰지 않아요"
  type        = string

  validation {
    condition     = can(regex("^[0-9a-f]{7,40}$", var.image_tag))
    error_message = "image_tag는 커밋 해시(16진수 7~40자)여야 해요."
  }
}

variable "port" {
  description = "컨테이너 안에서 앱이 요청을 받는 포트 (deploy.yaml port). Cloud Run이 PORT 환경변수로도 넣어 줘요"
  type        = number

  validation {
    condition     = var.port >= 1 && var.port <= 65535
    error_message = "port는 1~65535여야 해요."
  }
}

variable "healthcheck" {
  description = "헬스체크 경로 (deploy.yaml healthcheck). Cloud Run 시작 프로브가 200을 기대해요"
  type        = string
  default     = "/health"

  validation {
    condition     = startswith(var.healthcheck, "/")
    error_message = "healthcheck는 /로 시작해야 해요."
  }
}

variable "env" {
  description = "일반 환경변수 (deploy.yaml env 이름 + 값)"
  type        = map(string)
  default     = {}

  validation {
    # Cloud Run 예약어예요. port 변수로 넘겨요
    condition     = !contains(keys(var.env), "PORT")
    error_message = "PORT는 env에 넣지 않아요. port 변수를 써요."
  }
}

variable "secrets" {
  description = "비밀값 (deploy.yaml secrets 이름 + 값). 파일에 쓰지 않고 TF_VAR_secrets 환경변수로만 넘겨요"
  type        = map(string)
  default     = {}
  sensitive   = true
}

variable "database" {
  description = "DB 필요 여부 (deploy.yaml database). GCP Cloud SQL은 아직 지원하지 않아요 (SPEC §6, S 범위)"
  type        = bool
  default     = false

  validation {
    condition     = !var.database
    error_message = "GCP 기준 모듈은 아직 database = true를 지원하지 않아요 (Cloud SQL은 S 범위)."
  }
}

variable "memory" {
  description = "메모리 MiB (vCPU는 1로 고정: 1 미만은 동시성 1 같은 제약이 있어요)"
  type        = number
  default     = 512

  validation {
    condition     = contains([512, 1024, 2048], var.memory)
    error_message = "memory는 512, 1024, 2048 중 하나예요 (비용 상한)."
  }
}

variable "instances" {
  description = "최대 인스턴스 수. 요청이 없으면 0대라 과금이 없어요"
  type        = number
  default     = 1

  validation {
    condition     = var.instances >= 1 && var.instances <= 2
    error_message = "instances는 1~2예요 (비용 상한)."
  }
}

# ---------------------------------------------------------------- 대상 환경 등록값 (targets/gcp.json)

variable "project_id" {
  description = "GCP 프로젝트 ID"
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "project_id 형식이 맞지 않아요."
  }
}

variable "region" {
  description = "Cloud Run 리전. 도메인 매핑을 쓰려면 지원 리전이어야 해요 (서울 asia-northeast3은 미지원, 도쿄 asia-northeast1 지원)"
  type        = string
  default     = "asia-northeast1"
}

# ---------------------------------------------------------------- 공개 도메인 (대상 환경 등록값, 선택)
# 비우면 Cloud Run 기본 주소(https://…run.app)로 열어요. 넣으면 Cloud Run 도메인 매핑으로 <subdomain>.<domain>을 붙여요.
# 배포 서비스 계정이 Search Console에서 그 도메인의 확인된 소유자여야 하고, DNS에 <subdomain> CNAME → ghs.googlehosted.com이 있어야 해요.
# 인증서는 Google이 발급해요 (처음 15~60분)

variable "domain" {
  description = "공개 도메인. 비우면 도메인 없이 run.app 주소로 열어요"
  type        = string
  default     = ""
}

variable "subdomain" {
  description = "서비스 주소의 하위 도메인 (domain과 함께 써요)"
  type        = string
  default     = ""

  validation {
    condition     = var.domain == "" || can(regex("^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$", var.subdomain))
    error_message = "domain을 쓰면 subdomain은 소문자 · 숫자 · - 로 된 이름이어야 해요."
  }
}
