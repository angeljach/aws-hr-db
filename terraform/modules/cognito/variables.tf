variable "project_name" {
  type = string
}

variable "admin_user" {
  type = string
}

variable "admin_password" {
  type      = string
  sensitive = true
}

variable "limited_user" {
  type = string
}

variable "limited_password" {
  type      = string
  sensitive = true
}

variable "premium_user" {
  type = string
}

variable "premium_password" {
  type      = string
  sensitive = true
}
