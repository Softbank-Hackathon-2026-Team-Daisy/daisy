# Azure 기준 모듈: Container Apps (공개 호출, 요청 없으면 0대)
#
# - AI 생성의 참고 템플릿이자 N-02 실패 시 대안이에요 (infra/SPEC.md §6)
# - backend 블록은 쓰지 않아요. 러너가 backend.tf를 주입해요 (SPEC §3-4)
# - 자격증명은 러너 환경변수(ARM_CLIENT_ID · ARM_CLIENT_SECRET · ARM_TENANT_ID · ARM_SUBSCRIPTION_ID)로만 받아요. provider에 쓰지 않아요
# - 리소스 그룹과 Container Apps 환경은 준비 때 1번 만든 고정 리소스예요 (GCP 프로젝트 준비와 같아요).
#   환경의 기본 도메인이 바뀌지 않아서 DNS CNAME(<subdomain> → daisy-{name}.<기본 도메인>)도 그대로예요
# - 이미지는 공개 Docker Hub에서 직접 받아요 (amd64)

terraform {
  required_version = ">= 1.11"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.0"
    }
  }
}

provider "azurerm" {
  features {}

  # 공급자 등록은 구독 권한이 필요해서 준비 때 1번 해요. 배포 주체는 앱 리소스 그룹 권한만 있어요
  resource_provider_registrations = "none"
}

locals {
  prefix       = "daisy-${var.name}"
  image        = "${var.image}:${var.image_tag}"
  secret_names = nonsensitive(toset(keys(var.secrets)))

  tags = {
    Project   = "daisy"
    App       = var.name
    ManagedBy = "terraform"
  }

  # 공개 도메인을 넣으면 커스텀 도메인 + Azure 관리형 인증서 (variables.tf 맨 아래)
  custom   = var.domain != ""
  hostname = "${var.subdomain}.${var.domain}"
}

data "azurerm_container_app_environment" "this" {
  name                = var.environment_name
  resource_group_name = var.resource_group
}

# ---------------------------------------------------------------- Container App

resource "azurerm_container_app" "app" {
  name                         = local.prefix
  container_app_environment_id = data.azurerm_container_app_environment.this.id
  resource_group_name          = var.resource_group
  revision_mode                = "Single"
  workload_profile_name        = "Consumption" # 사용한 만큼만 과금 (전용 프로필 없음)
  max_inactive_revisions       = 2
  tags                         = local.tags

  # R-4: 비밀값은 Container Apps 비밀 저장소에 두고 env에서 이름으로 참조해요
  dynamic "secret" {
    for_each = local.secret_names
    content {
      name  = lower(replace(secret.value, "_", "-"))
      value = var.secrets[secret.value]
    }
  }

  # 인터넷 공개는 HTTPS만 (HTTP는 HTTPS로 넘겨요)
  ingress {
    external_enabled           = true
    allow_insecure_connections = false
    target_port                = var.port
    transport                  = "auto"

    traffic_weight {
      latest_revision = true
      percentage      = 100
    }
  }

  template {
    # 요청이 없으면 0대라 과금이 없어요
    min_replicas = 0
    max_replicas = var.instances

    container {
      name   = "app"
      image  = local.image
      cpu    = var.cpu
      memory = "${var.cpu * 2}Gi" # Consumption 조합: vCPU 1당 메모리 2Gi

      dynamic "env" {
        for_each = var.env
        content {
          name  = env.key
          value = env.value
        }
      }

      dynamic "env" {
        for_each = local.secret_names
        content {
          name        = env.value
          secret_name = lower(replace(env.value, "_", "-"))
        }
      }

      startup_probe {
        transport               = "HTTP"
        port                    = var.port
        path                    = var.healthcheck
        interval_seconds        = 3
        timeout                 = 2
        failure_count_threshold = 20
      }
    }
  }
}

# ---------------------------------------------------------------- 공개 도메인 (선택)
# DNS에 <subdomain> CNAME → 앱 기본 주소, asuid.<subdomain> TXT → 환경의 도메인 확인 ID가 먼저 있어야 해요.
# 인증서는 Azure가 발급해요 (처음 수 분~20분). 이미지만 바꾸는 재배포는 도메인 · 인증서를 그대로 써요

resource "azurerm_container_app_custom_domain" "app" {
  count = local.custom ? 1 : 0

  name             = local.hostname
  container_app_id = azurerm_container_app.app.id

  lifecycle {
    # 관리형 인증서는 Azure가 비동기로 붙여요. 이 값을 따라가면 매번 다시 만들어요
    ignore_changes = [certificate_binding_type, container_app_environment_certificate_id]
  }
}
