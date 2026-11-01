locals {
  name = "${var.project}-lambda"
}

module "shared" {
  source = "../modules/shared_lookup"

  project         = var.project
  hostname        = var.hostname
  repository_name = "${var.project}-lambda"
  image_tag       = var.image_tag
}

data "aws_iam_policy_document" "lambda_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "this" {
  name               = local.name
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

resource "aws_iam_role_policy_attachment" "logs" {
  role       = aws_iam_role.this.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_cloudwatch_log_group" "this" {
  name              = "/aws/lambda/${local.name}"
  retention_in_days = var.log_retention_days
}

resource "aws_lambda_function" "this" {
  function_name = local.name
  role          = aws_iam_role.this.arn
  package_type  = "Image"
  image_uri     = module.shared.image_uri
  architectures = ["x86_64"]
  memory_size   = var.memory_size
  timeout       = var.timeout

  environment {
    variables = {
      SECRET_WORD  = module.shared.secret_word
      AWS_LWA_PORT = "3000"
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.logs,
    aws_cloudwatch_log_group.this,
  ]
}

resource "aws_lb_target_group" "this" {
  name                               = local.name
  target_type                        = "lambda"
  lambda_multi_value_headers_enabled = false

  health_check {
    enabled  = false
    interval = 35
    timeout  = 30
  }
}

resource "aws_lambda_permission" "alb" {
  statement_id  = "AllowALBInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.this.function_name
  principal     = "elasticloadbalancing.amazonaws.com"
  source_arn    = aws_lb_target_group.this.arn
}

resource "aws_lb_target_group_attachment" "this" {
  target_group_arn = aws_lb_target_group.this.arn
  target_id        = aws_lambda_function.this.arn

  depends_on = [aws_lambda_permission.alb]
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
