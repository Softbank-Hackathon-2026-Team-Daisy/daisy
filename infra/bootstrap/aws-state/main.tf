# AWS state 버킷 (bootstrap, 1번만): 앱 · 고정 네트워크 · 이 스택의 state를 모두 여기에 둬요
#
# - 환경마다 그 환경의 저장소예요 (infra/SPEC.md §7-1). AWS 배포의 state는 AWS S3에만 둬요
# - 잠금은 S3 네이티브 잠금(use_lockfile)이라 DynamoDB가 필요 없어요. 러너가 backend 설정으로 켜요
# - 처음에는 로컬 state로 만들고, 바로 tf-run.sh migrate-state로 이 버킷에 옮겨요 (daisy-bootstrap이 해요)
# - 비용: state 파일 몇 개라 월 $0.01도 안 돼요
# - backend 블록은 쓰지 않아요. 러너가 주입해요

terraform {
  required_version = ">= 1.11"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project   = "daisy"
      Stack     = "state"
      ManagedBy = "terraform"
    }
  }
}

data "aws_caller_identity" "current" {}

resource "aws_s3_bucket" "state" {
  # 버킷 이름은 전 세계에서 하나라 계정 ID를 붙여요
  bucket = "${var.name}-tfstate-${data.aws_caller_identity.current.account_id}"
  # state가 남아 있으면 지우지 못하게 해요. 정말 지울 때는 버전까지 비운 뒤 지워요
  force_destroy = false
}

resource "aws_s3_bucket_ownership_controls" "state" {
  bucket = aws_s3_bucket.state.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket                  = aws_s3_bucket.state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# 잘못 덮어쓴 state를 되돌릴 수 있게 버전을 남겨요
resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id
  versioning_configuration {
    status = "Enabled"
  }
}

# state에는 비밀값이 들어가요 (R-5). SSE-S3는 무료예요
resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    id     = "expire-old-state-versions"
    status = "Enabled"
    filter {}

    noncurrent_version_expiration {
      noncurrent_days = var.noncurrent_days
    }
    abort_incomplete_multipart_upload {
      days_after_initiation = 1
    }
  }

  depends_on = [aws_s3_bucket_versioning.state]
}

# TLS가 아닌 요청은 거부해요
data "aws_iam_policy_document" "tls_only" {
  statement {
    sid     = "DenyInsecureTransport"
    effect  = "Deny"
    actions = ["s3:*"]
    resources = [
      aws_s3_bucket.state.arn,
      "${aws_s3_bucket.state.arn}/*",
    ]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "state" {
  bucket = aws_s3_bucket.state.id
  policy = data.aws_iam_policy_document.tls_only.json

  depends_on = [aws_s3_bucket_public_access_block.state]
}
