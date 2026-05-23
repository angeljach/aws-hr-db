variable "project_name" {
  type = string
}

variable "db_name" {
  type = string
}

variable "db_user" {
  type = string
}

variable "db_password" {
  type      = string
  sensitive = true
}

variable "vpc_id" {
  type = string
}

variable "db_subnet_group_id" {
  type = string
}

variable "db_security_group" {
  type = string
}
