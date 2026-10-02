variable "region" {
  description = "AWS 리전. 러너의 TF_STATE_REGION(기본 ap-northeast-2)과 같아야 해요"
  type        = string
  default     = "ap-northeast-2"
}

variable "name" {
  description = "버킷 이름 접두사. 버킷 이름은 <name>-tfstate-<계정 ID>예요"
  type        = string
  default     = "daisy"
}

variable "noncurrent_days" {
  description = "이전 state 버전을 남기는 기간 (일)"
  type        = number
  default     = 30
}
