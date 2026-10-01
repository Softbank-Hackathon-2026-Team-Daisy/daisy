# HTTPS를 쓰는 스택(aws-server, 시연 앱)이 이 인증서를 이름으로 찾아 써요

output "certificate_arn" {
  description = "*.도메인 와일드카드 인증서 (발급 완료)"
  value       = aws_acm_certificate_validation.wildcard.certificate_arn
}

output "zone_id" {
  description = "Route 53 호스팅 영역 ID"
  value       = data.aws_route53_zone.this.zone_id
}

output "domain" {
  description = "도메인"
  value       = var.domain
}
