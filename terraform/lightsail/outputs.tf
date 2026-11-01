output "url" {
  value = "https://${var.hostname}"
}

output "service_url" {
  value = aws_lightsail_container_service.this.url
}

output "certificate_validation_records" {
  value = [
    for o in aws_lightsail_certificate.this.domain_validation_options : {
      name  = o.resource_record_name
      type  = o.resource_record_type
      value = o.resource_record_value
    }
  ]
}

output "dns_record" {
  value = {
    name  = var.hostname
    type  = "CNAME"
    value = trimsuffix(trimprefix(aws_lightsail_container_service.this.url, "https://"), "/")
  }
}
