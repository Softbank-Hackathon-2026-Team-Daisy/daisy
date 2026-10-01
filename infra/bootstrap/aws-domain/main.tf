# 서비스 도메인 인증서 (bootstrap, 1번만): *.unibloom.cloud 와일드카드 ACM 인증서
#
# - 도메인은 Route 53에서 샀고, 호스팅 영역도 Route 53에 있어요. 이 스택은 영역을 만들지 않고 찾아서 써요
# - 인증서 하나로 ios.unibloom.cloud(심사용 서버) · aws.unibloom.cloud(시연) 등 하위 도메인을 모두 덮어요
# - DNS 검증 레코드를 같은 영역에 넣고, 발급될 때까지 기다려요 (보통 1~5분)
# - ACM 공인 인증서는 무료예요. 사용하는 ALB가 있는 동안 자동 갱신돼요
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
      Stack     = "domain"
      ManagedBy = "terraform"
    }
  }
}

data "aws_route53_zone" "this" {
  name         = var.domain
  private_zone = false
}

resource "aws_acm_certificate" "wildcard" {
  domain_name       = "*.${var.domain}"
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "validation" {
  for_each = {
    for o in aws_acm_certificate.wildcard.domain_validation_options : o.domain_name => o
  }

  zone_id         = data.aws_route53_zone.this.zone_id
  name            = each.value.resource_record_name
  type            = each.value.resource_record_type
  records         = [each.value.resource_record_value]
  ttl             = 300
  allow_overwrite = true
}

resource "aws_acm_certificate_validation" "wildcard" {
  certificate_arn         = aws_acm_certificate.wildcard.arn
  validation_record_fqdns = [for r in aws_route53_record.validation : r.fqdn]
}
