# AWS 기준 모듈 입력 변수. 이름은 deploy.yaml 키와 1:1이에요 (infra/AGENTS.md §4, SPEC §3-1).

variable "name" {
  description = "앱 이름 (deploy.yaml name). 리소스 이름 접두사 daisy-{name}에 써요"
  type        = string

  validation {
    # ALB 이름 32자 제한 때문에 20자 이하 (daisy-{name}-alb)
    condition     = can(regex("^[a-z][a-z0-9-]{1,19}$", var.name))
    error_message = "name은 소문자로 시작하는 2~20자(소문자·숫자·-)여야 해요."
  }
}

variable "image" {
  description = "태그 없는 이미지 주소 (예: docker.io/<계정>/hellocalc). 공개 이미지여야 해요"
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
  description = "헬스체크 경로 (deploy.yaml healthcheck). ALB 대상 그룹이 200을 기대해요"
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
    # Cloud Run 예약어라 환경 간 이식성을 위해 모든 모듈에서 막아요
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
  description = "DB 필요 여부 (deploy.yaml database). true면 RDS PostgreSQL을 private 서브넷에 만들어요"
  type        = bool
  default     = false
}

variable "cpu" {
  description = "vCPU (0.25 · 0.5 · 1)"
  type        = number
  default     = 0.25

  validation {
    condition     = contains([0.25, 0.5, 1], var.cpu)
    error_message = "cpu는 0.25, 0.5, 1 중 하나예요 (비용 상한)."
  }
}

variable "memory" {
  description = "메모리 MiB. Fargate가 허용하는 cpu 조합만 돼요"
  type        = number
  default     = 512

  validation {
    condition     = contains(["0.25/512", "0.25/1024", "0.25/2048", "0.5/1024", "0.5/2048", "1/2048"], "${var.cpu}/${var.memory}")
    error_message = "cpu/memory 조합은 0.25/512·1024·2048, 0.5/1024·2048, 1/2048만 돼요."
  }
}

variable "instances" {
  description = "실행할 태스크 개수"
  type        = number
  default     = 1

  validation {
    condition     = var.instances >= 1 && var.instances <= 2
    error_message = "instances는 1~2예요 (비용 상한)."
  }
}

variable "region" {
  description = "AWS 리전 (대상 환경 등록값)"
  type        = string
  default     = "ap-northeast-2"
}

# ---------------------------------------------------------------- 고정 네트워크 (대상 환경 등록값)
# infra/bootstrap/aws-network의 출력이에요. daisy-bootstrap이 targets/aws.json에 넣어 두면 러너가 넘겨줘요

variable "vpc_id" {
  description = "고정 VPC ID"
  type        = string

  validation {
    condition     = can(regex("^vpc-[0-9a-f]+$", var.vpc_id))
    error_message = "vpc_id는 vpc-로 시작해야 해요."
  }
}

variable "public_subnet_ids" {
  description = "ALB · 앱 태스크용 public 서브넷 ID (서로 다른 AZ 2개 이상)"
  type        = list(string)

  validation {
    condition     = length(var.public_subnet_ids) >= 2
    error_message = "ALB는 서로 다른 AZ의 public 서브넷이 2개 이상 필요해요."
  }
}

variable "private_subnet_ids" {
  description = "DB용 private 서브넷 ID (database = true일 때 2개 이상)"
  type        = list(string)
  default     = []

  validation {
    condition     = !var.database || length(var.private_subnet_ids) >= 2
    error_message = "database = true면 private 서브넷이 2개 이상 필요해요."
  }
}

# ---------------------------------------------------------------- 공개 도메인 (대상 환경 등록값, 선택)
# 비우면 ALB 주소(HTTP)로 열어요. 넣으면 aws-domain 스택의 *.<domain> 인증서로 HTTPS를 열고
# Route 53에 <subdomain>.<domain> → ALB 레코드를 만들어요. 예: aws.unibloom.cloud

variable "domain" {
  description = "Route 53 공개 호스팅 영역 도메인. 비우면 도메인 없이 ALB 주소로 열어요"
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
