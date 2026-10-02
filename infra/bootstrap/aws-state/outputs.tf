# daisy-bootstrap이 이 값으로 state를 옮기고, Jenkins 전역 환경변수 TF_STATE_BUCKET_AWS에 넣을 값을 알려 줘요

output "bucket" {
  description = "state 버킷 이름 (TF_STATE_BUCKET_AWS)"
  value       = aws_s3_bucket.state.id
}

output "region" {
  description = "state 버킷 리전 (TF_STATE_REGION)"
  value       = var.region
}
