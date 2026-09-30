# AWS 기준 모듈: ECS Fargate + ALB (+ database = true면 RDS PostgreSQL)
#
# - AI 생성의 참고 템플릿이자 N-02 실패 시 대안이에요 (infra/SPEC.md §5)
# - backend 블록은 쓰지 않아요. 러너가 backend.tf를 주입해요 (SPEC §3-4)
# - 자격증명은 러너 환경변수로만 받아요. provider에 profile·키를 쓰지 않아요
# - NAT Gateway 없이 이미지를 받으려고 태스크를 public 서브넷에 두고 공인 IP를 붙여요.
#   인바운드는 ALB 보안 그룹에서만 허용해서 태스크가 직접 노출되지 않아요

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
      App       = var.name
      ManagedBy = "terraform"
    }
  }
}

locals {
  prefix       = "daisy-${var.name}"
  image        = "${var.image}:${var.image_tag}"
  azs          = slice(data.aws_availability_zones.available.names, 0, 2)
  secret_names = nonsensitive(toset(keys(var.secrets)))
  db_port      = 5432

  # DB 접속 정보: 온프레미스·GCP와 같은 이름 (infra/AGENTS.md §4)
  db_env = var.database ? tomap({
    DB_HOST = aws_db_instance.this[0].address
    DB_PORT = tostring(local.db_port)
    DB_NAME = aws_db_instance.this[0].db_name
    DB_USER = aws_db_instance.this[0].username
  }) : tomap({})

  container_secrets = concat(
    [for k in local.secret_names : { name = k, valueFrom = aws_secretsmanager_secret.app[k].arn }],
    var.database ? [{ name = "DB_PASSWORD", valueFrom = "${aws_db_instance.this[0].master_user_secret[0].secret_arn}:password::" }] : [],
  )
  secret_arns = [for s in local.container_secrets : split(":password::", s.valueFrom)[0]]
}

data "aws_availability_zones" "available" {
  state = "available"
}

# ---------------------------------------------------------------- 네트워크

resource "aws_vpc" "this" {
  cidr_block           = "10.20.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = local.prefix }
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = { Name = local.prefix }
}

# ALB는 서로 다른 AZ의 서브넷 2개가 필수예요 (금지된 "Multi-AZ"는 DB 이중화 얘기)
resource "aws_subnet" "public" {
  count = 2

  vpc_id            = aws_vpc.this.id
  cidr_block        = cidrsubnet(aws_vpc.this.cidr_block, 8, count.index)
  availability_zone = local.azs[count.index]

  tags = { Name = "${local.prefix}-public-${count.index}" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = { Name = "${local.prefix}-public" }
}

resource "aws_route_table_association" "public" {
  count = 2

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# DB 전용. 인터넷 경로가 없는 기본 라우팅 테이블을 써요 (R-3)
resource "aws_subnet" "private" {
  count = var.database ? 2 : 0

  vpc_id            = aws_vpc.this.id
  cidr_block        = cidrsubnet(aws_vpc.this.cidr_block, 8, 10 + count.index)
  availability_zone = local.azs[count.index]

  tags = { Name = "${local.prefix}-private-${count.index}" }
}

# ---------------------------------------------------------------- 보안 그룹

resource "aws_security_group" "alb" {
  name        = "${local.prefix}-alb"
  description = "ALB: HTTP from the internet"
  vpc_id      = aws_vpc.this.id
}

# R-1: 인터넷 인바운드는 공개 LB의 80(·443)만
resource "aws_vpc_security_group_ingress_rule" "alb_http" {
  security_group_id = aws_security_group.alb.id
  description       = "HTTP from the internet"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
}

resource "aws_vpc_security_group_egress_rule" "alb_to_app" {
  security_group_id            = aws_security_group.alb.id
  description                  = "To app tasks"
  referenced_security_group_id = aws_security_group.app.id
  ip_protocol                  = "tcp"
  from_port                    = var.port
  to_port                      = var.port
}

resource "aws_security_group" "app" {
  name        = "${local.prefix}-app"
  description = "App tasks: only from the ALB"
  vpc_id      = aws_vpc.this.id
}

# R-2: 앱은 ALB에서만 받아요
resource "aws_vpc_security_group_ingress_rule" "app_from_alb" {
  security_group_id            = aws_security_group.app.id
  description                  = "From the ALB"
  referenced_security_group_id = aws_security_group.alb.id
  ip_protocol                  = "tcp"
  from_port                    = var.port
  to_port                      = var.port
}

# 허용 예외: 외부 레지스트리 이미지 pull · DB 접속 (SPEC §4-3)
resource "aws_vpc_security_group_egress_rule" "app_all" {
  security_group_id = aws_security_group.app.id
  description       = "Image pull from external registry, DB, AWS APIs"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

resource "aws_security_group" "db" {
  count = var.database ? 1 : 0

  name        = "${local.prefix}-db"
  description = "DB: only from app tasks"
  vpc_id      = aws_vpc.this.id
}

# R-3: DB는 앱 보안 그룹에서만
resource "aws_vpc_security_group_ingress_rule" "db_from_app" {
  count = var.database ? 1 : 0

  security_group_id            = aws_security_group.db[0].id
  description                  = "PostgreSQL from app tasks"
  referenced_security_group_id = aws_security_group.app.id
  ip_protocol                  = "tcp"
  from_port                    = local.db_port
  to_port                      = local.db_port
}

# ---------------------------------------------------------------- 로드밸런서

resource "aws_lb" "this" {
  name                       = "${local.prefix}-alb"
  load_balancer_type         = "application"
  security_groups            = [aws_security_group.alb.id]
  subnets                    = aws_subnet.public[*].id
  drop_invalid_header_fields = true
}

resource "aws_lb_target_group" "app" {
  name        = "${local.prefix}-tg"
  port        = var.port
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = aws_vpc.this.id

  # 기본 300초면 교체 배포가 5분 넘게 걸려요
  deregistration_delay = 30

  health_check {
    path                = var.healthcheck
    matcher             = "200"
    interval            = 10
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}

# ---------------------------------------------------------------- 비밀값 · 권한

resource "aws_secretsmanager_secret" "app" {
  for_each = local.secret_names

  name = "${local.prefix}/${each.key}"

  # 0이 아니면 destroy 후 같은 이름으로 다시 만드는 게 최대 30일 막혀요
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "app" {
  for_each = local.secret_names

  secret_id     = aws_secretsmanager_secret.app[each.key].id
  secret_string = var.secrets[each.key]
}

data "aws_iam_policy_document" "ecs_tasks_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "execution" {
  name               = "${local.prefix}-exec"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume.json
}

# ECS 표준 관리형 정책 (로그 쓰기 · ECR pull). 위험 검사에서 허용 예외예요 (SPEC §4-3)
resource "aws_iam_role_policy_attachment" "execution" {
  role       = aws_iam_role.execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# R-6: 실행 역할은 자기 비밀값만 읽어요
data "aws_iam_policy_document" "read_secrets" {
  count = length(local.secret_arns) > 0 ? 1 : 0

  statement {
    actions   = ["secretsmanager:GetSecretValue"]
    resources = local.secret_arns
  }
}

resource "aws_iam_role_policy" "read_secrets" {
  count = length(local.secret_arns) > 0 ? 1 : 0

  name   = "read-own-secrets"
  role   = aws_iam_role.execution.id
  policy = data.aws_iam_policy_document.read_secrets[0].json
}

# ---------------------------------------------------------------- 실행 (ECS Fargate)

resource "aws_cloudwatch_log_group" "app" {
  name              = "/daisy/${var.name}"
  retention_in_days = 3
}

resource "aws_ecs_cluster" "this" {
  name = local.prefix

  setting {
    name  = "containerInsights"
    value = "disabled"
  }
}

resource "aws_ecs_task_definition" "app" {
  family                   = local.prefix
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = tostring(var.cpu * 1024)
  memory                   = tostring(var.memory)
  execution_role_arn       = aws_iam_role.execution.arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }

  container_definitions = jsonencode([{
    name         = "app"
    image        = local.image
    essential    = true
    portMappings = [{ containerPort = var.port, protocol = "tcp" }]
    environment  = [for k, v in merge(var.env, local.db_env) : { name = k, value = v }]
    secrets      = local.container_secrets

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = aws_cloudwatch_log_group.app.name
        awslogs-region        = var.region
        awslogs-stream-prefix = "app"
      }
    }
  }])
}

resource "aws_ecs_service" "app" {
  name                              = local.prefix
  cluster                           = aws_ecs_cluster.this.id
  task_definition                   = aws_ecs_task_definition.app.arn
  desired_count                     = var.instances
  launch_type                       = "FARGATE"
  health_check_grace_period_seconds = 30

  # apply 성공 = 헬스 통과. 새 태그가 헬스에 실패하면 이전 버전으로 되돌리고 apply는 실패해요
  wait_for_steady_state = true

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  network_configuration {
    subnets          = aws_subnet.public[*].id
    security_groups  = [aws_security_group.app.id]
    assign_public_ip = true # NAT 없이 이미지를 받으려면 필요해요
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.app.arn
    container_name   = "app"
    container_port   = var.port
  }

  depends_on = [aws_lb_listener.http, aws_iam_role_policy_attachment.execution]
}

# ---------------------------------------------------------------- DB (database = true)

resource "aws_db_subnet_group" "this" {
  count = var.database ? 1 : 0

  name       = local.prefix
  subnet_ids = aws_subnet.private[*].id
}

resource "aws_db_instance" "this" {
  count = var.database ? 1 : 0

  identifier     = local.prefix
  engine         = "postgres"
  engine_version = "17"
  instance_class = "db.t4g.micro"
  db_name        = "app"
  username       = "app"

  # R-4: 비밀번호는 RDS가 Secrets Manager에 만들고 관리해요
  manage_master_user_password = true

  allocated_storage      = 20
  storage_type           = "gp3"
  storage_encrypted      = true
  multi_az               = false
  db_subnet_group_name   = aws_db_subnet_group.this[0].name
  vpc_security_group_ids = [aws_security_group.db[0].id]
  publicly_accessible    = false

  # 해커톤 중 destroy·재생성을 반복해요 (SPEC §4-3 허용 예외)
  backup_retention_period = 0
  skip_final_snapshot     = true
  deletion_protection     = false
  apply_immediately       = true
}
