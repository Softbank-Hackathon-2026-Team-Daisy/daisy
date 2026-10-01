# 고정 네트워크 (bootstrap, 1번만): 모든 앱이 같이 쓰는 VPC · 서브넷
#
# - 앱 배포(infra/modules/aws)는 여기서 만든 VPC · 서브넷 ID를 받아서 ALB · ECS만 만들어요 (infra/SPEC.md §5-0)
# - VPC · 서브넷 · IGW · 라우팅 테이블은 켜 둬도 무료예요. 앱을 지워도 그대로 둬요
# - NAT Gateway는 만들지 않아요. 앱 태스크는 public 서브넷 + 공인 IP로 이미지를 받아요
# - 대역 10.20.0.0/16은 온프레미스(172.16.1.0/24 · 172.16.2.0/24)와 겹치지 않아서 나중에 VPN을 붙일 수 있어요
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
      Stack     = "network"
      ManagedBy = "terraform"
    }
  }
}

data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  # ALB는 서로 다른 AZ의 서브넷 2개가 필수예요
  azs = slice(data.aws_availability_zones.available.names, 0, 2)
}

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = var.name }
}

# VPC가 자동으로 만드는 기본 보안 그룹은 규칙을 모두 비워 둬요. 앱은 자기 보안 그룹만 써요
resource "aws_default_security_group" "this" {
  vpc_id = aws_vpc.this.id

  tags = { Name = "${var.name}-default-unused" }
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = { Name = var.name }
}

# ALB와 앱 태스크용. 인터넷 경로가 있어요
resource "aws_subnet" "public" {
  count = 2

  vpc_id            = aws_vpc.this.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index)
  availability_zone = local.azs[count.index]

  tags = { Name = "${var.name}-public-${local.azs[count.index]}", Tier = "public" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = { Name = "${var.name}-public" }
}

resource "aws_route_table_association" "public" {
  count = 2

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# DB용. 인터넷 경로가 없어요 (R-3)
resource "aws_subnet" "private" {
  count = 2

  vpc_id            = aws_vpc.this.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, 10 + count.index)
  availability_zone = local.azs[count.index]

  tags = { Name = "${var.name}-private-${local.azs[count.index]}", Tier = "private" }
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.this.id

  tags = { Name = "${var.name}-private" }
}

resource "aws_route_table_association" "private" {
  count = 2

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}
