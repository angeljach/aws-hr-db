variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project name"
  type        = string
  default     = "aws-hr-db"
}

variable "environment" {
  description = "Environment (dev, staging, prod)"
  type        = string
  default     = "dev"
}

# Database
variable "db_name" {
  description = "Database name"
  type        = string
  default     = "hrdb"
  sensitive   = false
}

variable "db_user" {
  description = "Database master user"
  type        = string
  default     = "hrdbadmin"
  sensitive   = false
}

variable "db_password" {
  description = "Database master password"
  type        = string
  sensitive   = true
}

# Encryption
variable "encryption_key" {
  description = "AES-256 encryption key (base64 encoded 32 bytes)"
  type        = string
  sensitive   = true
}

# Cognito Users
variable "cognito_admin_user" {
  description = "Admin user email for Cognito"
  type        = string
  default     = "admin@example.com"
}

variable "cognito_admin_password" {
  description = "Admin user password for Cognito"
  type        = string
  sensitive   = true
}

variable "cognito_limited_user" {
  description = "Limited user email for Cognito"
  type        = string
  default     = "limited@example.com"
}

variable "cognito_limited_password" {
  description = "Limited user password for Cognito"
  type        = string
  sensitive   = true
}

variable "cognito_premium_user" {
  description = "Premium user email for Cognito"
  type        = string
  default     = "premium@example.com"
}

variable "cognito_premium_password" {
  description = "Premium user password for Cognito"
  type        = string
  sensitive   = true
}

# API Gateway
variable "api_stage" {
  description = "API Gateway stage name"
  type        = string
  default     = "dev"
}
