# 비밀값은 출력하지 않아요 (tf-run이 bootstrap 출력을 로그에 찍어요). 데모 계정 비밀번호는 secret_name을 콘솔에서 확인해요

output "service_url" {
  description = "iOS 앱이 접속하는 서버 주소"
  value       = "https://${local.hostname}"
}

output "alb_dns_name" {
  description = "ALB 주소 (DNS가 퍼지기 전 확인용)"
  value       = aws_lb.this.dns_name
}

output "secret_name" {
  description = "인증 키 · 데모 계정 비밀번호가 든 Secrets Manager 이름 (viewer 계정: judge)"
  value       = aws_secretsmanager_secret.app.name
}

output "image" {
  description = "지금 배포한 서버 이미지"
  value       = var.server_image
}
