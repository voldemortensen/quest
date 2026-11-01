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
  default = "lambda.insekure.com"
}

variable "listener_rule_priority" {
  type    = number
  default = 110
}

variable "memory_size" {
  type    = number
  default = 512
}

variable "timeout" {
  type    = number
  default = 15
}

variable "log_retention_days" {
  type    = number
  default = 7
}
