locals {
  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
  }

  lambda_runtime = "provided.al2023"  # For Go runtime (Amazon Linux 2023)
  
  # Sensitive fields for encryption
  sensitive_fields = [
    "salary",
    "phone",
    "address"
  ]

  # Role-based field access
  role_access = {
    admin = {
      include_fields = ["employee_id", "first_name", "last_name", "email", "department", "hire_date", "salary", "phone", "address"]
    }
    limited = {
      include_fields = ["employee_id", "first_name", "last_name", "email", "department", "hire_date"]
    }
    premium = {
      include_fields = ["employee_id", "first_name", "last_name", "email", "department", "hire_date", "phone"]
    }
  }
}
