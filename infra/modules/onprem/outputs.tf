output "service_url" {
  description = "Service VM 내부망에서 접근하는 HTTP 주소예요. 외부 HTTPS 주소는 별도로 연결해요."
  value       = "http://${var.host_ip}:${var.host_port}"
}
