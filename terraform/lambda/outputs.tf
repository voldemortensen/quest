output "url" {
  value = module.shared.url
}

output "function_name" {
  value = aws_lambda_function.this.function_name
}
