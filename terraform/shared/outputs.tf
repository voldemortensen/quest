output "vpc_id" {
  value = module.network.vpc_id
}

output "alb_dns_name" {
  value = aws_lb.this.dns_name
}

output "certificate_validation_records" {
  value = [
    for o in flatten(aws_acm_certificate.this[*].domain_validation_options) : {
      name  = o.resource_record_name
      type  = o.resource_record_type
      value = o.resource_record_value
    }
  ]
}

output "alb_dns_records" {
  value = [
    for h in var.alb_hostnames : {
      name  = h
      type  = "CNAME"
      value = aws_lb.this.dns_name
    }
  ]
}

output "ecr_repository_urls" {
  value = { for k, r in aws_ecr_repository.this : k => r.repository_url }
}

output "secret_word_parameter" {
  value = aws_ssm_parameter.secret_word.name
}
