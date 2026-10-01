# 필수 출력은 service_url이에요 (infra/AGENTS.md §4). 헬스체크 주소 = service_url + healthcheck

output "service_url" {
  description = "서비스 접속 URL (스킴 포함, 끝에 / 없음)"
  value       = "http://${aws_lb.this.dns_name}"
}

output "log_group" {
  description = "앱 로그가 쌓이는 CloudWatch 로그 그룹 (배포 실패 원인 확인용)"
  value       = aws_cloudwatch_log_group.app.name
}
