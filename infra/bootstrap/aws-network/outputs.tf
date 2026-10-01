# 앱 배포가 쓰는 값이에요. daisy-bootstrap이 대상 환경 등록값(targets/aws.json)에 자동으로 넣어요

output "vpc_id" {
  description = "고정 VPC ID"
  value       = aws_vpc.this.id
}

output "vpc_cidr" {
  description = "VPC 대역"
  value       = aws_vpc.this.cidr_block
}

output "public_subnet_ids" {
  description = "ALB · 앱 태스크용 public 서브넷 (AZ 2개)"
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "DB용 private 서브넷 (AZ 2개)"
  value       = aws_subnet.private[*].id
}

output "region" {
  description = "리전"
  value       = var.region
}
