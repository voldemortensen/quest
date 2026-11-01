locals {
  repositories = {
    app    = var.project
    lambda = "${var.project}-lambda"
  }
  certificate_arn = coalesce(var.certificate_arn, one(aws_acm_certificate_validation.this[*].certificate_arn))
}

module "network" {
  source = "../modules/network"

  name              = var.project
  cidr_block        = var.vpc_cidr
  az_count          = var.az_count
  nat_mode          = var.nat_mode
  nat_instance_type = var.nat_instance_type
}

resource "aws_ecr_repository" "this" {
  for_each = local.repositories

  name                 = each.value
  image_tag_mutability = "MUTABLE"
  force_delete         = var.ecr_force_delete

  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_ecr_lifecycle_policy" "this" {
  for_each = aws_ecr_repository.this

  repository = each.value.name
  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep last 5 images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 5
      }
      action = {
        type = "expire"
      }
    }]
  })
}

resource "aws_ssm_parameter" "secret_word" {
  name             = "/${var.project}/secret_word"
  type             = "SecureString"
  value_wo         = var.secret_word
  value_wo_version = var.secret_word_version
}

resource "aws_security_group" "alb" {
  name        = "${var.project}-alb"
  description = "Public ALB"
  vpc_id      = module.network.vpc_id

  tags = {
    Name = "${var.project}-alb"
  }
}

resource "aws_vpc_security_group_ingress_rule" "alb" {
  for_each = toset(["80", "443"])

  security_group_id = aws_security_group.alb.id
  cidr_ipv4         = var.allowed_ingress_cidr
  ip_protocol       = "tcp"
  from_port         = tonumber(each.value)
  to_port           = tonumber(each.value)
}

resource "aws_vpc_security_group_egress_rule" "alb_to_vpc" {
  security_group_id = aws_security_group.alb.id
  cidr_ipv4         = module.network.vpc_cidr_block
  ip_protocol       = "tcp"
  from_port         = 1024
  to_port           = 65535
}

resource "aws_lb" "this" {
  name                       = var.project
  load_balancer_type         = "application"
  internal                   = false
  security_groups            = [aws_security_group.alb.id]
  subnets                    = module.network.public_subnet_ids
  drop_invalid_header_fields = true
}

resource "aws_acm_certificate" "this" {
  count = var.certificate_arn == null ? 1 : 0

  domain_name               = var.alb_hostnames[0]
  subject_alternative_names = slice(var.alb_hostnames, 1, length(var.alb_hostnames))
  validation_method         = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_acm_certificate_validation" "this" {
  count = var.certificate_arn == null ? 1 : 0

  certificate_arn = aws_acm_certificate.this[0].arn
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

moved {
  from = aws_lb_listener.https["ecs"]
  to   = aws_lb_listener.https
}

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.this.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = local.certificate_arn

  default_action {
    type = "fixed-response"

    fixed_response {
      content_type = "text/plain"
      message_body = "unknown host"
      status_code  = "404"
    }
  }
}
