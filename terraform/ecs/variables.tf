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
  default = "ecs.insekure.com"
}

variable "listener_rule_priority" {
  type    = number
  default = 100
}

variable "desired_count" {
  type    = number
  default = 1
}

variable "cpu" {
  type    = number
  default = 256
}

variable "memory" {
  type    = number
  default = 512
}

variable "use_spot" {
  type    = bool
  default = true
}

variable "log_retention_days" {
  type    = number
  default = 7
}
