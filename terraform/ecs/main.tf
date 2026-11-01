locals {
  name           = "${var.project}-ecs"
  container_name = "app"
  container_port = 3000
  capacity       = var.use_spot ? "FARGATE_SPOT" : "FARGATE"
}

module "shared" {
  source = "../modules/shared_lookup"

  project         = var.project
  hostname        = var.hostname
  repository_name = var.project
  image_tag       = var.image_tag
}

resource "aws_ecs_cluster" "this" {
  name = local.name

  setting {
    name  = "containerInsights"
    value = "disabled"
  }
}

resource "aws_ecs_cluster_capacity_providers" "this" {
  cluster_name       = aws_ecs_cluster.this.name
  capacity_providers = ["FARGATE", "FARGATE_SPOT"]

  default_capacity_provider_strategy {
    capacity_provider = local.capacity
    weight            = 1
  }
}

resource "aws_cloudwatch_log_group" "this" {
  name              = "/ecs/${local.name}"
  retention_in_days = var.log_retention_days
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
  name               = "${local.name}-execution"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume.json
}

resource "aws_iam_role_policy_attachment" "execution" {
  role       = aws_iam_role.execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

data "aws_iam_policy_document" "execution_secrets" {
  statement {
    actions   = ["ssm:GetParameters"]
    resources = [module.shared.secret_word_arn]
  }
}

resource "aws_iam_role_policy" "execution_secrets" {
  name   = "secrets"
  role   = aws_iam_role.execution.id
  policy = data.aws_iam_policy_document.execution_secrets.json
}

resource "aws_ecs_task_definition" "this" {
  family                   = local.name
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.cpu
  memory                   = var.memory
  execution_role_arn       = aws_iam_role.execution.arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }

  container_definitions = jsonencode([{
    name      = local.container_name
    image     = module.shared.image_uri
    essential = true
    user      = "1000"
    portMappings = [{
      containerPort = local.container_port
      protocol      = "tcp"
    }]
    secrets = [{
      name      = "SECRET_WORD"
      valueFrom = module.shared.secret_word_arn
    }]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = aws_cloudwatch_log_group.this.name
        awslogs-region        = var.region
        awslogs-stream-prefix = local.container_name
      }
    }
  }])
}

resource "aws_security_group" "task" {
  name        = "${local.name}-task"
  description = "ECS tasks"
  vpc_id      = module.shared.vpc_id

  tags = {
    Name = "${local.name}-task"
  }
}

resource "aws_vpc_security_group_ingress_rule" "task_from_alb" {
  security_group_id            = aws_security_group.task.id
  referenced_security_group_id = module.shared.alb_security_group_id
  ip_protocol                  = "tcp"
  from_port                    = local.container_port
  to_port                      = local.container_port
}

resource "aws_vpc_security_group_egress_rule" "task_https" {
  security_group_id = aws_security_group.task.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
}

resource "aws_lb_target_group" "this" {
  name                 = local.name
  port                 = local.container_port
  protocol             = "HTTP"
  target_type          = "ip"
  vpc_id               = module.shared.vpc_id
  deregistration_delay = 30

  health_check {
    path    = "/"
    matcher = "200"
  }
}

resource "aws_lb_listener_rule" "this" {
  listener_arn = module.shared.listener_arn
  priority     = var.listener_rule_priority

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this.arn
  }

  condition {
    host_header {
      values = [var.hostname]
    }
  }
}

resource "aws_ecs_service" "this" {
  name                              = local.name
  cluster                           = aws_ecs_cluster.this.id
  task_definition                   = aws_ecs_task_definition.this.arn
  desired_count                     = var.desired_count
  health_check_grace_period_seconds = 30

  capacity_provider_strategy {
    capacity_provider = local.capacity
    weight            = 1
  }

  network_configuration {
    subnets          = module.shared.private_subnet_ids
    security_groups  = [aws_security_group.task.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.this.arn
    container_name   = local.container_name
    container_port   = local.container_port
  }

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  depends_on = [
    aws_lb_listener_rule.this,
    aws_ecs_cluster_capacity_providers.this,
  ]
}
