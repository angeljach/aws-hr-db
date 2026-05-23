resource "aws_cognito_user_pool" "main" {
  name = "${var.project_name}-pool"

  password_policy {
    minimum_length    = 8
    require_uppercase = true
    require_lowercase = true
    require_numbers   = true
    require_symbols   = false
  }

  auto_verified_attributes = ["email"]

  tags = {
    Name = "${var.project_name}-user-pool"
  }
}

resource "aws_cognito_user_pool_domain" "main" {
  domain       = "${replace(var.project_name, "aws-", "")}-${data.aws_caller_identity.current.account_id}"
  user_pool_id = aws_cognito_user_pool.main.id
}

resource "aws_cognito_user_pool_client" "main" {
  name            = "${var.project_name}-client"
  user_pool_id    = aws_cognito_user_pool.main.id
  explicit_auth_flows = [
    "ALLOW_USER_PASSWORD_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH"
  ]

  allowed_oauth_flows  = ["code", "implicit"]
  allowed_oauth_scopes = ["openid", "email", "profile"]
  
  callback_urls = ["http://localhost:8080/callback"]
  logout_urls   = ["http://localhost:8080/logout"]

  allowed_oauth_flows_user_pool_client = true
  
  supported_identity_providers = ["COGNITO"]
}

# Groups
resource "aws_cognito_user_group" "admin" {
  name         = "admin"
  user_pool_id = aws_cognito_user_pool.main.id
  description  = "Admin group with full access"
}

resource "aws_cognito_user_group" "limited" {
  name         = "limited"
  user_pool_id = aws_cognito_user_pool.main.id
  description  = "Limited group with non-sensitive field access"
}

resource "aws_cognito_user_group" "premium" {
  name         = "premium"
  user_pool_id = aws_cognito_user_pool.main.id
  description  = "Premium group with non-sensitive + 2 sensitive fields"
}

# Users
resource "aws_cognito_user" "admin" {
  user_pool_id       = aws_cognito_user_pool.main.id
  username           = var.admin_user
  password           = var.admin_password

  attributes = {
    email          = var.admin_user
    email_verified = true
  }

  depends_on = [aws_cognito_user_pool.main]
}

resource "aws_cognito_user_in_group" "admin" {
  user_pool_id = aws_cognito_user_pool.main.id
  username     = aws_cognito_user.admin.username
  group_name   = aws_cognito_user_group.admin.name
}

resource "aws_cognito_user" "limited" {
  user_pool_id       = aws_cognito_user_pool.main.id
  username           = var.limited_user
  password           = var.limited_password

  attributes = {
    email          = var.limited_user
    email_verified = true
  }

  depends_on = [aws_cognito_user_pool.main]
}

resource "aws_cognito_user_in_group" "limited" {
  user_pool_id = aws_cognito_user_pool.main.id
  username     = aws_cognito_user.limited.username
  group_name   = aws_cognito_user_group.limited.name
}

resource "aws_cognito_user" "premium" {
  user_pool_id       = aws_cognito_user_pool.main.id
  username           = var.premium_user
  password           = var.premium_password

  attributes = {
    email          = var.premium_user
    email_verified = true
  }

  depends_on = [aws_cognito_user_pool.main]
}

resource "aws_cognito_user_in_group" "premium" {
  user_pool_id = aws_cognito_user_pool.main.id
  username     = aws_cognito_user.premium.username
  group_name   = aws_cognito_user_group.premium.name
}

data "aws_caller_identity" "current" {}
