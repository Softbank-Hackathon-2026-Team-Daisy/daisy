variable "region" {
  description = "AWS 리전. 앱 모듈의 region과 같아야 해요"
  type        = string
  default     = "ap-northeast-2"
}

variable "name" {
  description = "네트워크 리소스 이름 접두사"
  type        = string
  default     = "daisy"
}

variable "vpc_cidr" {
  description = "VPC 대역 (/16). 온프레미스 172.16.1.0/24 · 172.16.2.0/24와 겹치면 안 돼요"
  type        = string
  default     = "10.20.0.0/16"

  validation {
    condition     = can(cidrnetmask(var.vpc_cidr)) && endswith(var.vpc_cidr, "/16")
    error_message = "vpc_cidr는 /16 대역이어야 해요 (서브넷을 /24로 나눠요)."
  }
}
