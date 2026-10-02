# Unibloom 서버 (bootstrap): iOS 앱 심사 · TestFlight가 접속하는 HTTPS 서버. 시연 배포와 따로 계속 떠 있어요
#
# - https://ios.unibloom.cloud → ALB(443, 80은 443으로) → ECS Fargate(server/ Spring Boot) → RDS PostgreSQL
# - 이미지는 daisy-bootstrap이 server/ 소스로 빌드해서 server_image로 넘겨요 (infra/images/server/Dockerfile)
# - 비밀값은 코드 · 로그에 없어요 (R-4): DB 비밀번호는 RDS가 Secrets Manager에 만들고, 인증 키 · 데모 계정
#   비밀번호는 무작위로 만들어 Secrets Manager에 넣어요. 데모 계정 비밀번호는 콘솔에서 확인해요 (출력하지 않아요)
# - 고정 네트워크(aws-network)의 VPC · 서브넷과 인증서(aws-domain)를 태그 · 이름으로 찾아요
# - 2026-10-04(일) 18:00까지 유지하고 지워요. 비용 약 $0.08/시간 (ALB · Fargate 0.5 vCPU/1GB · RDS t4g.micro · 공인 IPv4)
# - backend 블록은 쓰지 않아요. 러너가 주입해요

terraform {
  required_version = ">= 1.11"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project   = "daisy"
      Stack     = "server"
      App       = var.name
      ManagedBy = "terraform"
    }
  }
}

locals {
  prefix   = "daisy-${var.name}"
  hostname = "${var.subdomain}.${var.domain}"
  port     = 8080
}

# ── 고정 리소스 찾기 ───────────────────────────────────────────

data "aws_vpc" "this" {
  tags = { Project = "daisy", Stack = "network" }
}

data "aws_subnets" "public" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.this.id]
  }
  tags = { Tier = "public" }
}

data "aws_subnets" "private" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.this.id]
  }
  tags = { Tier = "private" }
}

data "aws_route53_zone" "this" {
  name         = var.domain
  private_zone = false
}

data "aws_acm_certificate" "wildcard" {
  domain      = "*.${var.domain}"
  statuses    = ["ISSUED"]
  most_recent = true
}

# ── 비밀값 (R-4) ───────────────────────────────────────────────

resource "random_password" "auth_secret" {
  length  = 48 # HS256 서명 키는 32바이트 이상이어야 해요
  special = false
}

resource "random_password" "owner" {
  length  = 20
  special = false
}

resource "random_password" "viewer" {
  length  = 16 # 심사자가 직접 입력해요
  special = false
}

resource "aws_secretsmanager_secret" "app" {
  name                    = "${local.prefix}/app"
  description             = "Unibloom 서버 인증 키 · 데모 계정 비밀번호 (owner: daisy, viewer: judge)"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "app" {
  secret_id = aws_secretsmanager_secret.app.id
  secret_string = jsonencode({
    auth_secret     = random_password.auth_secret.result
    owner_password  = random_password.owner.result
    viewer_password = random_password.viewer.result
  })
}

# ── 보안 그룹: 인터넷 → ALB(80 · 443) → 앱(8080) → DB(5432) ──────

resource "aws_security_group" "alb" {
  name        = "${local.prefix}-alb"
  description = "${local.prefix} ALB: HTTP/HTTPS from the internet"
  vpc_id      = data.aws_vpc.this.id
}

resource "aws_vpc_security_group_ingress_rule" "alb" {
  for_each          = toset(["80", "443"])
  security_group_id = aws_security_group.alb.id
  cidr_ipv4         = "0.0.0.0/0" # R-1: LB의 80 · 443만
  from_port         = tonumber(each.key)
  to_port           = tonumber(each.key)
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "alb_to_app" {
  security_group_id            = aws_security_group.alb.id
  referenced_security_group_id = aws_security_group.app.id
  from_port                    = local.port
  to_port                      = local.port
  ip_protocol                  = "tcp"
}

resource "aws_security_group" "app" {
  name        = "${local.prefix}-app"
  description = "${local.prefix} tasks: only from the ALB"
  vpc_id      = data.aws_vpc.this.id
}

resource "aws_vpc_security_group_ingress_rule" "app_from_alb" {
  security_group_id            = aws_security_group.app.id
  referenced_security_group_id = aws_security_group.alb.id # R-2
  from_port                    = local.port
  to_port                      = local.port
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "app_all" {
  security_group_id = aws_security_group.app.id
  cidr_ipv4         = "0.0.0.0/0" # 이미지 pull · Secrets Manager · RDS
  ip_protocol       = "-1"
}

resource "aws_security_group" "db" {
  name        = "${local.prefix}-db"
  description = "${local.prefix} database: only from the tasks"
  vpc_id      = data.aws_vpc.this.id
}

resource "aws_vpc_security_group_ingress_rule" "db_from_app" {
  security_group_id            = aws_security_group.db.id
  referenced_security_group_id = aws_security_group.app.id # R-3
  from_port                    = 5432
  to_port                      = 5432
  ip_protocol                  = "tcp"
}

# ── 로드밸런서 (HTTPS) ─────────────────────────────────────────

resource "aws_lb" "this" {
  name               = "${local.prefix}-alb"
  load_balancer_type = "application"
  internal           = false
  security_groups    = [aws_security_group.alb.id]
  subnets            = data.aws_subnets.public.ids
}

resource "aws_lb_target_group" "app" {
  name                 = "${local.prefix}-tg"
  port                 = local.port
  protocol             = "HTTP"
  target_type          = "ip"
  vpc_id               = data.aws_vpc.this.id
  deregistration_delay = 30

  health_check {
    path                = "/actuator/health" # 인증 없이 열려 있어요 (BearerAuthFilter)
    matcher             = "200"
    interval            = 15
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }
}

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.this.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = data.aws_acm_certificate.wildcard.arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"
    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

resource "aws_route53_record" "this" {
  zone_id = data.aws_route53_zone.this.zone_id
  name    = local.hostname
  type    = "A"

  alias {
    name                   = aws_lb.this.dns_name
    zone_id                = aws_lb.this.zone_id
    evaluate_target_health = true
  }
}

# ── DB (RDS PostgreSQL) ────────────────────────────────────────

resource "aws_db_subnet_group" "this" {
  name       = local.prefix
  subnet_ids = data.aws_subnets.private.ids
}

resource "aws_db_instance" "this" {
  identifier     = local.prefix
  engine         = "postgres"
  engine_version = "17"
  instance_class = "db.t4g.micro"
  db_name        = "daisy"
  username       = "daisy"

  # R-4: 비밀번호는 RDS가 Secrets Manager에 만들고 관리해요
  manage_master_user_password = true

  allocated_storage       = 20
  storage_type            = "gp3"
  storage_encrypted       = true # R-5
  multi_az                = false
  publicly_accessible     = false # R-3
  db_subnet_group_name    = aws_db_subnet_group.this.name
  vpc_security_group_ids  = [aws_security_group.db.id]
  backup_retention_period = 1
  skip_final_snapshot     = true # 일요일에 지워요
  deletion_protection     = false
}

# ── 실행 (ECS Fargate) ─────────────────────────────────────────

resource "aws_cloudwatch_log_group" "app" {
  name              = "/daisy/${var.name}"
  retention_in_days = 3
}

data "aws_iam_policy_document" "assume_ecs_tasks" {
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
  assume_role_policy = data.aws_iam_policy_document.assume_ecs_tasks.json
}

resource "aws_iam_role_policy_attachment" "execution" {
  role       = aws_iam_role.execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# R-6: 자기 비밀값 두 개만 읽어요
data "aws_iam_policy_document" "read_secrets" {
  statement {
    actions = ["secretsmanager:GetSecretValue"]
    resources = [
      aws_secretsmanager_secret.app.arn,
      aws_db_instance.this.master_user_secret[0].secret_arn,
    ]
  }
}

resource "aws_iam_role_policy" "read_secrets" {
  name   = "read-own-secrets"
  role   = aws_iam_role.execution.id
  policy = data.aws_iam_policy_document.read_secrets.json
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
  cpu                      = var.cpu
  memory                   = var.memory
  execution_role_arn       = aws_iam_role.execution.arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }

  container_definitions = jsonencode([{
    name         = "app"
    image        = var.server_image
    essential    = true
    portMappings = [{ containerPort = local.port, protocol = "tcp" }]

    environment = [
      { name = "DAISY_DB_URL", value = "jdbc:postgresql://${aws_db_instance.this.address}:${aws_db_instance.this.port}/daisy" },
      { name = "DAISY_DB_USER", value = aws_db_instance.this.username },
      { name = "DAISY_CORS_ORIGINS", value = join(",", var.cors_origins) },
    ]
    secrets = [
      { name = "DAISY_DB_PASSWORD", valueFrom = "${aws_db_instance.this.master_user_secret[0].secret_arn}:password::" },
      { name = "DAISY_AUTH_SECRET", valueFrom = "${aws_secretsmanager_secret.app.arn}:auth_secret::" },
      { name = "DAISY_DEMO_OWNER_PASSWORD", valueFrom = "${aws_secretsmanager_secret.app.arn}:owner_password::" },
      { name = "DAISY_DEMO_VIEWER_PASSWORD", valueFrom = "${aws_secretsmanager_secret.app.arn}:viewer_password::" },
    ]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = aws_cloudwatch_log_group.app.name
        awslogs-region        = var.region
        awslogs-stream-prefix = "app"
      }
    }
  }])

  depends_on = [aws_secretsmanager_secret_version.app]
}

resource "aws_ecs_service" "app" {
  name                              = local.prefix
  cluster                           = aws_ecs_cluster.this.id
  task_definition                   = aws_ecs_task_definition.app.arn
  desired_count                     = 1
  launch_type                       = "FARGATE"
  health_check_grace_period_seconds = 180 # Spring Boot 기동 · Flyway 마이그레이션 시간

  # apply 성공 = 헬스 통과. 새 이미지가 헬스에 실패하면 이전 버전으로 되돌려요 (서버가 내려가지 않게)
  wait_for_steady_state = true

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  network_configuration {
    subnets          = data.aws_subnets.public.ids
    security_groups  = [aws_security_group.app.id]
    assign_public_ip = true # NAT 없이 이미지 · Secrets Manager에 접근해요
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.app.arn
    container_name   = "app"
    container_port   = local.port
  }

  depends_on = [aws_lb_listener.https, aws_iam_role_policy.read_secrets, aws_iam_role_policy_attachment.execution]
}
