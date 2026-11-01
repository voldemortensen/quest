data "aws_vpc" "this" {
  tags = {
    Name = var.project
  }
}

data "aws_subnets" "private" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.this.id]
  }

  tags = {
    Tier = "private"
  }
}

data "aws_subnets" "public" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.this.id]
  }

  tags = {
    Tier = "public"
  }
}

data "aws_lb" "this" {
  name = var.project
}

data "aws_security_group" "alb" {
  name   = "${var.project}-alb"
  vpc_id = data.aws_vpc.this.id
}

data "aws_lb_listener" "this" {
  load_balancer_arn = data.aws_lb.this.arn
  port              = 443
}

data "aws_ssm_parameter" "secret_word" {
  name = "/${var.project}/secret_word"
}

data "aws_ecr_repository" "this" {
  name = var.repository_name
}

data "aws_ecr_image" "this" {
  repository_name = data.aws_ecr_repository.this.name
  image_tag       = var.image_tag
}
