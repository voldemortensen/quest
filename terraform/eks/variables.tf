variable "project" {
  type    = string
  default = "quest"
}

variable "region" {
  type    = string
  default = "us-west-2"
}

variable "image_tag" {
  type    = string
  default = "latest"
}

variable "hostname" {
  type    = string
  default = "eks.insekure.com"
}

variable "listener_rule_priority" {
  type    = number
  default = 120
}

variable "kubernetes_version" {
  type    = string
  default = "1.36"
}

variable "api_allowed_cidrs" {
  type    = list(string)
  default = ["0.0.0.0/0"]
}

variable "node_instance_types" {
  type    = list(string)
  default = ["t3a.small", "t3.small"]
}

variable "use_spot" {
  type    = bool
  default = true
}

variable "node_count" {
  type    = number
  default = 1
}

variable "replicas" {
  type    = number
  default = 2
}

variable "node_port" {
  type    = number
  default = 30080
}
