output "vpc_id" {
  value = data.aws_vpc.this.id
}

output "private_subnet_ids" {
  value = data.aws_subnets.private.ids
}

output "public_subnet_ids" {
  value = data.aws_subnets.public.ids
}

output "alb_dns_name" {
  value = data.aws_lb.this.dns_name
}

output "alb_security_group_id" {
  value = data.aws_security_group.alb.id
}

output "listener_arn" {
  value = data.aws_lb_listener.this.arn
}

output "url" {
  value = "https://${var.hostname}"
}

output "secret_word_arn" {
  value = data.aws_ssm_parameter.secret_word.arn
}

output "secret_word" {
  value     = data.aws_ssm_parameter.secret_word.value
  sensitive = true
}

output "image_uri" {
  value = "${data.aws_ecr_repository.this.repository_url}@${data.aws_ecr_image.this.image_digest}"
}
