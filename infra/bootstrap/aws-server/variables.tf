variable "region" {
  description = "AWS 리전"
  type        = string
  default     = "ap-northeast-2"
}

variable "name" {
  description = "리소스 이름 접두사 (daisy-<name>)"
  type        = string
  default     = "unibloom"
}

variable "domain" {
  description = "Route 53 도메인. 인증서는 aws-domain 스택의 *.도메인이에요"
  type        = string
  default     = "unibloom.cloud"
}

variable "subdomain" {
  description = "서버 주소의 하위 도메인. iOS 앱 심사용"
  type        = string
  default     = "ios"
}

variable "server_image" {
  description = "서버 이미지 전체 주소 (태그 포함, latest 금지). daisy-bootstrap이 TF_VAR_server_image로 넘겨요"
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9.-]+(:[0-9]+)?/[a-z0-9._/-]+:[0-9a-f]{7,40}$", var.server_image))
    error_message = "server_image는 <레지스트리>/<저장소>:<커밋 해시>여야 해요."
  }
}

variable "cpu" {
  description = "Fargate vCPU 단위 (512 = 0.5 vCPU)"
  type        = number
  default     = 512
}

variable "memory" {
  description = "Fargate 메모리 (MiB). Spring Boot는 1GB가 안전해요"
  type        = number
  default     = 1024
}

variable "cors_origins" {
  description = "브라우저에서 이 서버를 부를 수 있는 출처. iOS 앱은 CORS와 상관없어요"
  type        = list(string)
  default     = ["https://ios.unibloom.cloud"]
}
