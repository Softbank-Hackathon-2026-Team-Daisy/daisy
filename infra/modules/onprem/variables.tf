variable "image" {
  description = "태그 없는 이미지 주소예요. 태그는 image_tag로 전달해요."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9.-]+(:[0-9]+)?/[a-z0-9._/-]+$", var.image))
    error_message = "image는 레지스트리를 포함한 태그 없는 이미지 주소여야 해요."
  }
}

variable "image_tag" {
  description = "이미지 태그인 커밋 해시예요. CI에서는 40자 전체 해시를 전달해요."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-f]{7,40}$", var.image_tag))
    error_message = "image_tag는 커밋 해시(16진수 7~40자)여야 해요."
  }
}

variable "port" {
  description = "컨테이너 안에서 앱이 요청을 받는 포트예요."
  type        = number

  validation {
    condition     = var.port >= 1 && var.port <= 65535 && floor(var.port) == var.port
    error_message = "port는 1~65535 사이 정수여야 해요."
  }
}

variable "docker_host" {
  description = "Service VM의 Docker SSH 주소예요. 예: ssh://user@172.16.1.5:22"
  type        = string

  validation {
    condition     = startswith(var.docker_host, "ssh://")
    error_message = "docker_host는 ssh://로 시작해야 해요."
  }
}

variable "ssh_key_path" {
  description = "Terraform 실행 호스트에 있는 SSH 개인키 파일 경로예요. 키 내용은 넣지 않아요."
  type        = string
}

variable "known_hosts_path" {
  description = "Terraform 실행 호스트에 있는 검증된 SSH known_hosts 파일 경로예요."
  type        = string
}

variable "host_ip" {
  description = "포트를 바인딩하고 service_url에 사용할 Service VM의 IPv4 주소예요."
  type        = string

  validation {
    condition     = can(cidrnetmask("${var.host_ip}/32")) && var.host_ip != "0.0.0.0"
    error_message = "host_ip는 0.0.0.0이 아닌 Service VM의 IPv4 주소여야 해요."
  }
}

variable "host_port" {
  description = "Service VM에 게시할 포트예요. 컨테이너 내부 port와 구분해요."
  type        = number

  validation {
    condition     = var.host_port >= 1 && var.host_port <= 65535 && floor(var.host_port) == var.host_port
    error_message = "host_port는 1~65535 사이 정수여야 해요."
  }
}
