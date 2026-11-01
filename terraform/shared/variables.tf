variable "project" {
  type    = string
  default = "quest"
}

variable "region" {
  type    = string
  default = "us-west-2"
}

variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "az_count" {
  type    = number
  default = 2
}

variable "nat_mode" {
  type    = string
  default = "instance"
}

variable "nat_instance_type" {
  type    = string
  default = "t4g.nano"
}

variable "allowed_ingress_cidr" {
  type    = string
  default = "0.0.0.0/0"
}

variable "alb_hostnames" {
  type    = list(string)
  default = ["ecs.insekure.com", "lambda.insekure.com", "eks.insekure.com"]
}

variable "certificate_arn" {
  type    = string
  default = null
}

variable "secret_word" {
  type      = string
  sensitive = true
  ephemeral = true
}

variable "secret_word_version" {
  type    = number
  default = 1
}

variable "ecr_force_delete" {
  type    = bool
  default = true
}
