# Azure 기준 모듈 입력 변수. 이름은 deploy.yaml 키와 1:1이에요 (infra/AGENTS.md §4, SPEC §3-1). AWS · GCP 모듈과 같은 계약이에요

variable "name" {
  description = "앱 이름 (deploy.yaml name). 리소스 이름 접두사 daisy-{name}에 써요"
  type        = string

  validation {
    # Container App 이름 32자 제한 때문에 26자 이하 (daisy-{name})
    condition     = can(regex("^[a-z][a-z0-9-]{0,24}[a-z0-9]$", var.name)) && !strcontains(var.name, "--")
    error_message = "name은 소문자로 시작하고 소문자 · 숫자로 끝나는 2~26자(소문자·숫자·-, -- 없음)여야 해요."
  }
}

variable "image" {
  description = "태그 없는 이미지 주소 (예: docker.io/<계정>/hellocalc). Container Apps가 직접 받으려면 공개 이미지여야 해요"
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
  description = "컨테이너 안에서 앱이 요청을 받는 포트 (deploy.yaml port)"
  type        = number

  validation {
    condition     = var.port >= 1 && var.port <= 65535
    error_message = "port는 1~65535여야 해요."
  }
}

variable "healthcheck" {
  description = "헬스체크 경로 (deploy.yaml healthcheck). 시작 프로브가 200을 기대해요"
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
}

variable "secrets" {
  description = "비밀값 (deploy.yaml secrets 이름 + 값). 파일에 쓰지 않고 TF_VAR_secrets 환경변수로만 넘겨요"
  type        = map(string)
  default     = {}
  sensitive   = true
}

variable "database" {
  description = "DB 필요 여부 (deploy.yaml database). Azure DB는 아직 지원하지 않아요 (SPEC §6, S 범위)"
  type        = bool
  default     = false

  validation {
    condition     = !var.database
    error_message = "Azure 기준 모듈은 아직 database = true를 지원하지 않아요 (S 범위)."
  }
}

variable "cpu" {
  description = "vCPU. 메모리는 Consumption 조합대로 vCPU의 2배(Gi)예요"
  type        = number
  default     = 0.25

  validation {
    condition     = contains([0.25, 0.5, 1], var.cpu)
    error_message = "cpu는 0.25, 0.5, 1 중 하나예요 (비용 상한)."
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

# ---------------------------------------------------------------- 대상 환경 등록값 (targets/azure.json)
# 구독 · 테넌트는 러너 환경변수(ARM_SUBSCRIPTION_ID · ARM_TENANT_ID)로 받아요

variable "resource_group" {
  description = "앱을 만들 리소스 그룹 (준비 때 만든 것, 예: daisy-apps). 배포 주체는 이 그룹에만 권한이 있어요"
  type        = string
}

variable "environment_name" {
  description = "Container Apps 환경 이름 (준비 때 만든 것, 예: daisy-env)"
  type        = string
}

# ---------------------------------------------------------------- 공개 도메인 (대상 환경 등록값, 선택)
# 비우면 Container Apps 기본 주소(https://…azurecontainerapps.io)로 열어요. 넣으면 <subdomain>.<domain>을 붙여요.
# DNS에 <subdomain> CNAME → daisy-{name}.<환경 기본 도메인>, asuid.<subdomain> TXT → 환경의 도메인 확인 ID가 있어야 해요

variable "domain" {
  description = "공개 도메인. 비우면 도메인 없이 기본 주소로 열어요"
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
