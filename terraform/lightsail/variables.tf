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

variable "power" {
  type    = string
  default = "nano"
}

variable "scale" {
  type    = number
  default = 1
}

variable "hostname" {
  type    = string
  default = "lightsail.insekure.com"
}
