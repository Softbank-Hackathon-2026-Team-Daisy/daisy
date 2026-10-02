# 필수 출력은 service_url이에요 (infra/AGENTS.md §4). 헬스체크 주소 = service_url + healthcheck

output "service_url" {
  description = "서비스 접속 URL (스킴 포함, 끝에 / 없음). 도메인을 쓰면 그 주소, 아니면 Cloud Run 기본 주소"
  value       = local.custom ? "https://${local.hostname}" : google_cloud_run_v2_service.app.uri
}

output "run_url" {
  description = "Cloud Run 기본 주소 (도메인 인증서가 발급되기 전에도 열려요)"
  value       = google_cloud_run_v2_service.app.uri
}
