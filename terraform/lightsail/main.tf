locals {
  container_name = "app"
  container_port = 3000
}

data "aws_ecr_repository" "app" {
  name = var.project
}

data "aws_ecr_image" "app" {
  repository_name = data.aws_ecr_repository.app.name
  image_tag       = var.image_tag
}

data "aws_ssm_parameter" "secret_word" {
  name = "/${var.project}/secret_word"
}

resource "aws_lightsail_certificate" "this" {
  name        = var.project
  domain_name = var.hostname
}

resource "aws_lightsail_container_service" "this" {
  name  = "${var.project}-lightsail"
  power = var.power
  scale = var.scale

  public_domain_names {
    certificate {
      certificate_name = aws_lightsail_certificate.this.name
      domain_names     = [var.hostname]
    }
  }

  private_registry_access {
    ecr_image_puller_role {
      is_active = true
    }
  }
}

data "aws_iam_policy_document" "ecr_pull" {
  statement {
    sid     = "AllowLightsailPull"
    actions = ["ecr:BatchGetImage", "ecr:GetDownloadUrlForLayer"]

    principals {
      type        = "AWS"
      identifiers = [aws_lightsail_container_service.this.private_registry_access[0].ecr_image_puller_role[0].principal_arn]
    }
  }
}

resource "aws_ecr_repository_policy" "lightsail" {
  repository = data.aws_ecr_repository.app.name
  policy     = data.aws_iam_policy_document.ecr_pull.json
}

resource "aws_lightsail_container_service_deployment_version" "this" {
  service_name = aws_lightsail_container_service.this.name

  container {
    container_name = local.container_name
    image          = "${data.aws_ecr_repository.app.repository_url}:${var.image_tag}"

    environment = {
      SECRET_WORD  = data.aws_ssm_parameter.secret_word.value
      IMAGE_DIGEST = data.aws_ecr_image.app.image_digest
    }

    ports = {
      (local.container_port) = "HTTP"
    }
  }

  public_endpoint {
    container_name = local.container_name
    container_port = local.container_port

    health_check {
      path                = "/"
      success_codes       = "200-299"
      healthy_threshold   = 2
      unhealthy_threshold = 2
      interval_seconds    = 10
      timeout_seconds     = 5
    }
  }

  depends_on = [aws_ecr_repository_policy.lightsail]
}
