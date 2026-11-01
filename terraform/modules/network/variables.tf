variable "name" {
  type = string
}

variable "cidr_block" {
  type = string
}

variable "az_count" {
  type    = number
  default = 2
}

variable "nat_mode" {
  type    = string
  default = "instance"

  validation {
    condition     = contains(["instance", "gateway", "none"], var.nat_mode)
    error_message = "nat_mode must be one of: instance, gateway, none."
  }
}

variable "nat_instance_type" {
  type    = string
  default = "t4g.nano"
}
