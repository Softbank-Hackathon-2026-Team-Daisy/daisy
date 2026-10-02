variable "region" {
  description = "AWS 리전. 인증서는 ALB와 같은 리전에 있어야 해요"
  type        = string
  default     = "ap-northeast-2"
}

variable "domain" {
  description = "Route 53에서 산 도메인 (호스팅 영역 이름)"
  type        = string
  default     = "unibloom.cloud"
}
