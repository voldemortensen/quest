locals {
  name           = "${var.project}-eks"
  container_port = 3000
  labels = {
    app = var.project
  }
}

module "shared" {
  source = "../modules/shared_lookup"

  project         = var.project
  hostname        = var.hostname
  repository_name = var.project
  image_tag       = var.image_tag
}

data "aws_iam_policy_document" "cluster_assume" {
  statement {
    actions = ["sts:AssumeRole", "sts:TagSession"]

    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "cluster" {
  name               = "${local.name}-cluster"
  assume_role_policy = data.aws_iam_policy_document.cluster_assume.json
}

resource "aws_iam_role_policy_attachment" "cluster" {
  role       = aws_iam_role.cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

resource "aws_eks_cluster" "this" {
  name     = local.name
  version  = var.kubernetes_version
  role_arn = aws_iam_role.cluster.arn

  access_config {
    authentication_mode                         = "API"
    bootstrap_cluster_creator_admin_permissions = true
  }

  vpc_config {
    subnet_ids              = module.shared.private_subnet_ids
    endpoint_private_access = true
    endpoint_public_access  = true
    public_access_cidrs     = var.api_allowed_cidrs
  }

  upgrade_policy {
    support_type = "STANDARD"
  }

  depends_on = [aws_iam_role_policy_attachment.cluster]
}

data "aws_iam_policy_document" "node_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "node" {
  name               = "${local.name}-node"
  assume_role_policy = data.aws_iam_policy_document.node_assume.json
}

resource "aws_iam_role_policy_attachment" "node" {
  for_each = toset([
    "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy",
    "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy",
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly",
  ])

  role       = aws_iam_role.node.name
  policy_arn = each.value
}

resource "aws_eks_node_group" "this" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "default"
  node_role_arn   = aws_iam_role.node.arn
  subnet_ids      = module.shared.private_subnet_ids
  ami_type        = "AL2023_x86_64_STANDARD"
  capacity_type   = var.use_spot ? "SPOT" : "ON_DEMAND"
  instance_types  = var.node_instance_types
  disk_size       = 20

  scaling_config {
    desired_size = var.node_count
    min_size     = var.node_count
    max_size     = var.node_count + 1
  }

  update_config {
    max_unavailable = 1
  }

  depends_on = [aws_iam_role_policy_attachment.node]
}

resource "aws_vpc_security_group_ingress_rule" "node_port_from_alb" {
  security_group_id            = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
  referenced_security_group_id = module.shared.alb_security_group_id
  ip_protocol                  = "tcp"
  from_port                    = var.node_port
  to_port                      = var.node_port
}

resource "aws_lb_target_group" "this" {
  name                 = local.name
  port                 = var.node_port
  protocol             = "HTTP"
  target_type          = "instance"
  vpc_id               = module.shared.vpc_id
  deregistration_delay = 30

  health_check {
    path    = "/"
    matcher = "200"
  }
}

resource "aws_autoscaling_attachment" "this" {
  autoscaling_group_name = aws_eks_node_group.this.resources[0].autoscaling_groups[0].name
  lb_target_group_arn    = aws_lb_target_group.this.arn
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

resource "kubernetes_namespace_v1" "this" {
  metadata {
    name = var.project
  }

  depends_on = [aws_eks_node_group.this]
}

resource "kubernetes_secret_v1" "this" {
  metadata {
    name      = var.project
    namespace = kubernetes_namespace_v1.this.metadata[0].name
  }

  data = {
    SECRET_WORD = module.shared.secret_word
  }
}

resource "kubernetes_deployment_v1" "this" {
  metadata {
    name      = var.project
    namespace = kubernetes_namespace_v1.this.metadata[0].name
    labels    = local.labels
  }

  spec {
    replicas = var.replicas

    selector {
      match_labels = local.labels
    }

    template {
      metadata {
        labels = local.labels
      }

      spec {
        container {
          name  = "app"
          image = module.shared.image_uri

          port {
            container_port = local.container_port
          }

          env {
            name = "SECRET_WORD"

            value_from {
              secret_key_ref {
                name = kubernetes_secret_v1.this.metadata[0].name
                key  = "SECRET_WORD"
              }
            }
          }

          resources {
            requests = {
              cpu    = "50m"
              memory = "64Mi"
            }
            limits = {
              memory = "256Mi"
            }
          }

          readiness_probe {
            http_get {
              path = "/secret_word"
              port = local.container_port
            }
          }

          security_context {
            run_as_non_root            = true
            run_as_user                = 1000
            allow_privilege_escalation = false
          }
        }
      }
    }
  }
}

resource "kubernetes_service_v1" "this" {
  metadata {
    name      = var.project
    namespace = kubernetes_namespace_v1.this.metadata[0].name
  }

  spec {
    type     = "NodePort"
    selector = local.labels

    port {
      port        = 80
      target_port = local.container_port
      node_port   = var.node_port
    }
  }
}
