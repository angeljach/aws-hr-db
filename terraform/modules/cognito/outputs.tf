output "user_pool_id" {
  value = aws_cognito_user_pool.main.id
}

output "user_pool_arn" {
  value = aws_cognito_user_pool.main.arn
}

output "client_id" {
  value = aws_cognito_user_pool_client.main.id
}

output "domain" {
  value = aws_cognito_user_pool_domain.main.domain
}

output "admin_username" {
  value = aws_cognito_user.admin.username
}

output "limited_username" {
  value = aws_cognito_user.limited.username
}

output "premium_username" {
  value = aws_cognito_user.premium.username
}
