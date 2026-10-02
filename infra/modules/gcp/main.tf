# GCP 기준 모듈: Cloud Run (전용 런타임 서비스 계정, 공개 호출, 요청 없으면 0대)
#
# - AI 생성의 참고 템플릿이자 N-02 실패 시 대안이에요 (infra/SPEC.md §6)
# - backend 블록은 쓰지 않아요. 러너가 backend.tf를 주입해요 (SPEC §3-4)
# - 자격증명은 러너 환경변수(GOOGLE_APPLICATION_CREDENTIALS)로만 받아요. provider에 credentials를 쓰지 않아요
# - API 활성화는 프로젝트 준비 때 1번 해요 (run · iam · secretmanager · storage). 모듈에서 켜면 지울 때 API가 꺼져요
# - 이미지는 공개 Docker Hub에서 직접 받아요. Cloud Run은 amd64만 실행해서 CI가 amd64 · arm64를 같이 올려요

terraform {
  required_version = ">= 1.11"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 8.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region

  default_labels = {
    project    = "daisy"
    app        = var.name
    managed-by = "terraform"
  }
}

locals {
  prefix       = "daisy-${var.name}"
  image        = "${var.image}:${var.image_tag}"
  secret_names = nonsensitive(toset(keys(var.secrets)))

  # 공개 도메인을 넣으면 Cloud Run 도메인 매핑 (variables.tf 맨 아래)
  custom   = var.domain != ""
  hostname = "${var.subdomain}.${var.domain}"
}

# ---------------------------------------------------------------- 런타임 서비스 계정 (R-6: 기본 Compute SA를 쓰지 않아요)

resource "google_service_account" "run" {
  account_id   = "${local.prefix}-run"
  display_name = "${local.prefix} Cloud Run runtime"
}

# ---------------------------------------------------------------- 비밀값 (R-4: Secret Manager에 두고 참조해요)

resource "google_secret_manager_secret" "app" {
  for_each = local.secret_names

  secret_id = "${local.prefix}-${lower(replace(each.key, "_", "-"))}"

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "app" {
  for_each = local.secret_names

  secret      = google_secret_manager_secret.app[each.key].id
  secret_data = var.secrets[each.key]
}

# 런타임 서비스 계정은 자기 비밀값만 읽어요
resource "google_secret_manager_secret_iam_member" "app" {
  for_each = local.secret_names

  secret_id = google_secret_manager_secret.app[each.key].id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.run.email}"
}

# ---------------------------------------------------------------- Cloud Run

resource "google_cloud_run_v2_service" "app" {
  name     = local.prefix
  location = var.region
  ingress  = "INGRESS_TRAFFIC_ALL"

  # provider 기본값이 삭제 보호라 끄지 않으면 지울 때 실패해요 (해커톤 중 지우고 다시 만들어요)
  deletion_protection = false

  template {
    service_account = google_service_account.run.email

    # 요청이 없으면 0대라 과금이 없어요
    scaling {
      min_instance_count = 0
      max_instance_count = var.instances
    }

    containers {
      image = local.image

      # Cloud Run이 PORT 환경변수를 넣어 줘요 (env에 PORT를 넣으면 에러)
      ports {
        container_port = var.port
      }

      resources {
        limits = {
          cpu    = "1"
          memory = "${var.memory}Mi"
        }
        cpu_idle = true # 요청을 처리할 때만 CPU 과금
      }

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
          name = env.value
          value_source {
            secret_key_ref {
              secret  = google_secret_manager_secret.app[env.value].secret_id
              version = "latest"
            }
          }
        }
      }

      startup_probe {
        http_get {
          path = var.healthcheck
        }
        period_seconds    = 3
        timeout_seconds   = 2
        failure_threshold = 20
      }
    }
  }

  depends_on = [google_secret_manager_secret_version.app, google_secret_manager_secret_iam_member.app]
}

# 누구나 호출할 수 있게 공개해요 (웹 서비스). 다른 역할은 주지 않아요
resource "google_cloud_run_v2_service_iam_member" "public" {
  name     = google_cloud_run_v2_service.app.name
  location = google_cloud_run_v2_service.app.location
  role     = "roles/run.invoker"
  member   = "allUsers"
}

# ---------------------------------------------------------------- 공개 도메인 (선택)
# 서비스를 이미지만 바꿔 다시 배포해도 매핑 · 인증서는 그대로예요. 서비스를 지우면 같이 지워져요

resource "google_cloud_run_domain_mapping" "app" {
  count = local.custom ? 1 : 0

  name     = local.hostname
  location = var.region

  metadata {
    namespace = var.project_id
  }

  spec {
    route_name = google_cloud_run_v2_service.app.name
  }
}
