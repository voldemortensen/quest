output "url" {
  value = module.shared.url
}

output "cluster_name" {
  value = aws_eks_cluster.this.name
}

output "kubeconfig_command" {
  value = "aws eks update-kubeconfig --region ${var.region} --name ${aws_eks_cluster.this.name}"
}
